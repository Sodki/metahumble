import std.algorithm.searching;
import std.array;
import std.conv;
import std.datetime;
import std.digest.md;
import std.digest.sha;
import std.exception;
import std.file;
import std.parallelism;
import std.path;
import std.stdio;
import std.string;

import ae.sys.file;
import ae.utils.funopt;
import ae.utils.main;
import ae.utils.time.format;
import ae.utils.xmllite;

void verify(bool verify)
{
	auto date = Clock.currTime().formatTime!"Y-m-d";
	auto oldDir = "../dl/old/" ~ date;
	auto badDir = oldDir.buildPath("bad");
	auto unknownDir = oldDir.buildPath("unknown");

	auto xml = xmlParse(readText("../dl/hb.metalink"));
	bool[string] sawFile;
	auto mutex = new Object;
fileLoop:
	foreach (file; xml["metalink"]["files"].children.parallel)
	{
		auto fn = file.attributes["name"];
		synchronized(mutex) sawFile[fn] = true;

		foreach (url; file["resources"])
			if (url.attributes["type"] == "bittorrent")
			{
				auto torrentFn = url.text.findSplit("?")[0].split("/")[$-1];
				synchronized(mutex) sawFile[torrentFn] = true;
			}

		auto path = "../dl/" ~ fn;
		if (!path.exists)
			continue;

		string result = "OK";
		try
		{
			if (auto size = file.findChild("size"))
				enforce(size.text.to!int == path.getSize(), "Bad size");

			if (verify)
				if (auto verification = file.findChild("verification"))
					foreach (hash; verification)
					{
						void checkHash(alias Digest)()
						{
							auto result = path.fileDigest!Digest.toHexString!(LetterCase.lower)();
							enforce(hash.text == result,
								"Bad %ssum: Expected %s, got %s".format(hash.attributes["type"], hash.text, result));
						}

						if (hash.attributes["type"] == "md5")
							checkHash!MD5();
						else
						if (hash.attributes["type"] == "sha1")
						{
							// HB-provided SHA1s seem to be often wrong, disabled temporarily.
							// Support request #366674 submitted on Sun 2016-05-22 05:34 UTC
							//checkHash!SHA1();
						}
						else
							enforce(false, "Unknown hash algorithm: " ~ hash.attributes["type"]);
					}
		}
		catch (Exception e)
		{
			result = e.msg;
			synchronized(mutex)
			{
				badDir.ensureDirExists();
				File(badDir.buildPath("descript.ion"), "ab").writeln(fn, " ", e.msg);
				rename("../dl/" ~ fn, badDir.buildPath(fn));
			}
		}

		synchronized(mutex)
		{
			writeln(fn);
			writeln(" >> ", result);
		}
	}

	foreach (de; dirEntries("../dl", SpanMode.shallow))
		if (de.isFile && de.extension != ".metalink" && de.baseName !in sawFile)
		{
			writeln(de.baseName);
			writeln(" >> Not in metalink");
			unknownDir.ensureDirExists();
			rename(de.name, unknownDir.buildPath(de.baseName));
		}

	foreach (fn, b; sawFile)
		if (!exists("../dl/" ~ fn) && !fn.endsWith(".torrent"))
		{
			writeln(fn);
			writeln(" >> Not on disk");
		}
}

mixin main!(funopt!verify);
