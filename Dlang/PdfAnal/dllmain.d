module dllmain;

import std.c.windows.windows;
import core.sys.windows.dll;
import PdfLexer;
import PdfStream;
import PdfObjects;
import PdfDocument;

__gshared HINSTANCE g_hInst;

extern (Windows)
BOOL DllMain(HINSTANCE hInstance, ULONG ulReason, LPVOID pvReserved)
{
    final switch (ulReason)
    {
	case DLL_PROCESS_ATTACH:
	    g_hInst = hInstance;
	    dll_process_attach( hInstance, true );
	    break;

	case DLL_PROCESS_DETACH:
	    dll_process_detach( hInstance, true );
	    break;

	case DLL_THREAD_ATTACH:
	    dll_thread_attach( true, true );
	    break;

	case DLL_THREAD_DETACH:
	    dll_thread_detach( true, true );
	    break;
    }
    return true;
}

string fromExt(char *src)
{
	version(Windows) {
		import std.windows.charset;
		return std.windows.charset.fromMBSz(cast(immutable char*)src);
	}
	else {
	}
}

class DocHolder
{
	this(PdfDocument doc) { doc_ = doc; }
	PdfDocument doc_;
	ubyte[] resBuf_;
}

DocHolder[ulong] objectTable;
ulong key_ = 0;

export extern(C)
{
	ulong getPdfDocument(char *fpathz)
	{
		auto fpath = fromExt(fpathz);
		if(!std.file.exists(fpath)) {
			return 0;
		}
		auto doc = new PdfDocument();
		doc.loadDocument(fpath);
		objectTable[++key_] = new DocHolder(doc);
		return key_;
	}

	void closeDocument(ulong key)
	{
		if(key in objectTable) {
			objectTable[key] = null;
			objectTable.remove(key);
			core.memory.GC.collect();
		}
	}

	ulong analDocument(ulong key)
	{
		if(key !in objectTable) {
			return 0;
		}
		auto holder = objectTable[key];
		auto doc = holder.doc_;

		char[] buf;
		buf ~= "[[";

		foreach(ti, t; doc.getTrailers()) {
			if(ti != 0) {
				buf ~= ",";
			}
			buf ~= t.toString();
		}

		buf ~= "],\n[";
		foreach(int i, tbl; doc.xrefTables) {
			//"type:%s num:%d offset:%d".format(tbl.type, i, tbl.ofs).writeln;
			/**/
			if(i != 0) {
				buf ~= ",";
			}
			auto obj = doc.getObject(i);
			if(obj !is null) {
				buf ~= obj.toString();
			}
			else {
				buf ~= "null";
			}
			//*/
		}
		buf ~= "]]";

		holder.resBuf_ = cast(ubyte[])buf;

		return buf.length + 1;
	}

	ulong analObjStream(ulong key, int objno)
	{
		if(key !in objectTable) {
			return 0;
		}
		if(objno < 0) {
			//"spcific objno option at stream command".writeln;
			return 0;
		}
		auto holder = objectTable[key];
		auto doc = holder.doc_;

		doc.getObject(objno);	// for loding stream offset
		delete holder.resBuf_;
		// dupしないと中身が壊されるようだ。。。
		holder.resBuf_ = doc.getStream(objno).dup;

		return holder.resBuf_.length;
	}

	void getBuff(ulong key, ubyte* buf)
	{
		if(key !in objectTable) {
			return;
		}
		auto holder = objectTable[key];
		foreach(char c; holder.resBuf_) {
			*(buf++) = c;
		}
	}
}
