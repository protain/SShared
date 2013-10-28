module dllmain;

import std.c.windows.windows;
import std.conv;
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
	~this()
	{
		delete doc_;
		delete resBuf_;
	}
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
		doc.loadPageTree();
		objectTable[++key_] = new DocHolder(doc);
		return key_;
	}

	void closeDocument(ulong key)
	{
		if(key in objectTable) {
			auto holder = objectTable[key];
			delete holder;
			objectTable[key] = null;
			objectTable.remove(key);
			core.memory.GC.collect();
		}
	}

	ulong analPages(ulong key)
	{
		if(key !in objectTable) {
			return 0;
		}
		auto holder = objectTable[key];
		auto doc = holder.doc_;

		char[] buf;
		buf ~= "[";
		foreach(i, p; doc.pages) {
			if(i != 0) {
				buf ~= ",";
			}
			buf ~= p.toString();
		}
		buf ~= "]";
		holder.resBuf_ = cast(ubyte[])buf;

		return buf.length + 1;
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

		delete holder.resBuf_;
		holder.resBuf_ = cast(ubyte[])buf;

		return buf.length + 1;
	}

	ulong analObject(ulong key, int objno)
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

		auto obj = doc.getObject(objno);
		if(obj is null) {
			return 0;
		}
		delete holder.resBuf_;
		holder.resBuf_ = cast(ubyte[])obj.toString();

		return holder.resBuf_.length;
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
		// broken resBuf_ when no duplicate,
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

	bool updateObjectStream(ulong key, int objno, ubyte* buff, ulong buflen)
	{
		if(key !in objectTable) {
			return false;
		}
		if(objno < 0) {
			//"spcific objno option at stream command".writeln;
			return false;
		}
		auto holder = objectTable[key];
		auto doc = holder.doc_;
		ubyte[] buf;
		for(int i = 0; i < buflen; ++i) {
			buf ~= buff[i];
		}
		return doc.setStream(objno, buf);
	}

	bool updateObjectValue(ulong key, int objno, char *keyz, char *valuez)
	{
		if(key !in objectTable) {
			return false;
		}
		if(objno < 0) {
			//"spcific objno option at stream command".writeln;
			return false;
		}
		auto holder = objectTable[key];
		auto doc = holder.doc_;

		auto objkey = fromExt(keyz);
		auto value = fromExt(valuez);
		auto obj = doc.getObject(objno);	// for loding stream offset
		auto vobj = obj.dictGets(objkey);
		if(vobj is null) {
			return false;
		}
		auto trg = cast(PdfDictionary)obj;
		PdfObject nvobj;
		switch(vobj.kind) {
		case PdfObjKind.PDF_INT:
			trg.putValue(objkey, new PdfPrimitive(to!int(value)));
			break;
		case PdfObjKind.PDF_REAL:
			trg.putValue(objkey, new PdfPrimitive(to!float(value)));
			break;
		case PdfObjKind.PDF_BOOL:
			trg.putValue(objkey, new PdfPrimitive(to!bool(value)));
			break;
		case PdfObjKind.PDF_STRING, PdfObjKind.PDF_NAME:
			trg.putValue(objkey, new PdfString(
				objkey, vobj.kind == PdfObjKind.PDF_NAME));
			break;
		default:
			return false;
		}

		return true;
	}

	void saveDocument(ulong key, char *fpathz)
	{
		if(key !in objectTable) {
			return;
		}
		try {
			auto holder = objectTable[key];
			auto opt = new PdfDocument.PdfSaveOption;
			auto fpath = fromExt(fpathz);
			holder.doc_.writeDocument(fpath, opt);
		}
		catch(Throwable e) {
			auto msg = e.text;
			throw e;
		}
	}
}
