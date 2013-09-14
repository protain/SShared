module PdfDocument;

import std.stdio;
import std.conv;
import std.string;
import std.file;
import std.array;

import PdfLexer;
import PdfStream;
import PdfObjects;
import PdfPage;
import PdfDecoder;

class XRefTable
{
public:
	char type = 0x00;
	size_t ofs;
	int gen;
	size_t streamOnFS;
	PdfObject obj;
	ubyte[] stmBuff;
}

class PdfDocument
{
private:
	MemoryReader reader_;
	PdfLexer lexer_;
	int version_;
	size_t startxref_;
	XRefTable[] tables_;
	PdfDictionary[] trailer_;
	PdfPage[] pages_;

public:
	@property PdfLexer lexer()
	{
		return lexer_;
	}

	@property MemoryReader reader()
	{
		return reader_;
	}

	@property int pdfVersion()
	{
		return version_;
	}

	@property XRefTable[] xrefTables()
	{
		return tables_;
	}

	@property int pageLength()
	{
		if(pages_ is null) {
			return -1;
		}
		return cast(int)pages_.length;
	}

	@property PdfPage[] pages()
	{
		return pages_;
	}

	private void init()
	{
		reader_ = null;
		lexer_ = null;
		tables_ = null;
		version_ = 0;
		trailer_ = null;
		pages_ = null;
	}

	this()
	{
		init();
	}

	void loadDocument(string fname)
	{
		init();
		reader_ = new MemoryReader(cast(ubyte[])std.file.read(fname));
		lexer_ = new PdfLexer(reader_);
		loadVersion();
		readStartXRef();
		trailer_ ~= readTrailer();

		int size = trailer_[0].getValue("Size").value!int;
		if(size == 0) {
			throw new Error("trailer missing Size entry");
		}
		size_t xrefstmofs, prevofs = 0;
		PdfDictionary trailer = trailer_[0];
		do {
			//trailer.toString().writeln;

			auto prevObj = trailer.getValue("Prev");
			prevofs = (prevObj is null) ? 0 : prevObj.value!size_t;
			auto xrefsObj = trailer.getValue("XRefStm");
			xrefstmofs = (xrefsObj is null) ? 0 : xrefsObj.value!size_t;
			if(prevofs && xrefstmofs) {
				trailer = cast(PdfDictionary)readXRef(xrefstmofs);
				trailer_ ~= trailer;
			}
			size_t ofs = 0;
			if(prevofs) {
				ofs = prevofs;
			}
			else if(xrefstmofs) {
				ofs = xrefstmofs;
			}
			if(ofs) {
				trailer = cast(PdfDictionary)readXRef(ofs);
				trailer_ ~= trailer;
			}
		} while(xrefstmofs || prevofs);
	}

	PdfObject dictGetIndObj(PdfObject dict, string key)
	{
		auto obj = dict.dictGets(key);
		if(obj is null) {
			return null;
		}
		if(obj.kind != PdfObjKind.PDF_INDIRECT) {
			return obj;
		}
		auto objnum = obj.value!(int[])[0];
		return getObject(objnum);
	}

	PdfObject getIndObj(PdfObject indobj)
	{
		if(indobj is null || indobj.kind != PdfObjKind.PDF_INDIRECT) {
			return indobj;
		}
		return getObject(indobj.value!(int[])[0]);
	}

	void loadPageTree()
	{
		if(trailer_ is null || trailer_.length < 1) {
			throw new Error("PdfDocument not loaded.");
		}
		auto catalog = trailer_[0].getValue("Root");
		if(catalog.kind != PdfObjKind.PDF_DICT) {
			if(catalog.kind != PdfObjKind.PDF_INDIRECT) {
				throw new Error("missing page tree");
			}
			auto objno = catalog.value!(int[])[0];
			catalog = getObject(objno);
			//to!string(catalog).writeln;
		}
		auto pages = dictGetIndObj(catalog, "Pages");
		auto count = dictGetIndObj(pages, "Count");

		if(pages is null) {
			throw new Error("missing page tree");
		}
		if(count is null) {
			throw new Error("missing page count");
		}
		loadPageTreeNode(pages);
	}

	private void loadPageTreeNode(PdfObject node)
	{
		struct PdfPageInfo
		{
			PdfObject resources_;
			PdfObject mediabox_;
			PdfObject cropbox_;
			PdfObject rotate_;
		}
		class PageLoad
		{
			PdfArray kids_;
			PdfObject node_;
			int max_;
			int pos_;
			PdfPageInfo info_;
		}
		PageLoad stack[];
		pages_ = null;
		int stacklen = -1;
		int pageCap = 0;
		int pageLen = 0;
		PdfPageInfo info;
		do {
			if(node is null) {

			}
			else {
				auto kids = dictGetIndObj(node, "Kids");
				auto count = dictGetIndObj(node, "Count");
				if(kids !is null && kids.kind == PdfObjKind.PDF_ARRAY &&
					count !is null && count.kind == PdfObjKind.PDF_INT && count.value!(int))
				{
					auto obj = node.dictGets("Resources");
					if(obj !is null) {
						info.resources_ = obj;
					}
					obj = node.dictGets("MediaBox");
					if(obj !is null) {
						info.mediabox_ = obj;
					}
					obj = node.dictGets("CropBox");
					if(obj !is null) {
						info.cropbox_ = obj;
					}
					obj = node.dictGets("Rotate");
					if(obj !is null) {
						info.rotate_ = obj;
					}
					//"stacklen:%d".format(stacklen).writeln;
					stack.length = (++stacklen + 1);
					if(stack[stacklen] is null) {
						stack[stacklen] = new PageLoad;
					}
					stack[stacklen].kids_ = cast(PdfArray)kids;
					stack[stacklen].node_ = node;
					stack[stacklen].pos_ = -1;
					stack[stacklen].max_ = kids.arrayLen;
					stack[stacklen].info_ = info;
				}
				else if(node.kind == PdfObjKind.PDF_DICT) {
					auto dict = cast(PdfDictionary)node;
					if(info.resources_ !is null && dict.getValue("Resources") is null) {
						dict.dictPuts("Resources", info.resources_);
					}	
					if(info.mediabox_ !is null && dict.getValue("MediaBox") is null) {
						dict.dictPuts("MediaBox", info.mediabox_);
					}	
					if(info.cropbox_ !is null && dict.getValue("CropBox") is null) {
						dict.dictPuts("CropBox", info.cropbox_);
					}	
					if(info.rotate_ !is null && dict.getValue("Rotate") is null) {
						dict.dictPuts("Rotate", info.rotate_);
					}
					if(pageLen == pageCap) {
						pageCap++;
						pages_.length = pageCap;
					}
					pages_[pageLen] = new PdfPage(this, cast(PdfDictionary)dict);
					++pageLen;
				}
				if(stacklen < 0) {
					break;
				}
				while(++stack[stacklen].pos_ == stack[stacklen].max_) {
					stacklen--;
					if(stacklen < 0) {
						break;
					}
					node = stack[stacklen].node_;
					info = stack[stacklen].info_;
				}
				if(stacklen >= 0) {
					node = getIndObj(stack[stacklen].kids_.arrayGets(stack[stacklen].pos_));
				}
			}
		} while(stacklen >= 0);
	}

	PdfDictionary[] getTrailers()
	{
		if(trailer_ is null || trailer_.length == 0) {
			throw new Error("PdfDocument not loaded.");
		}
		return trailer_;
	}

	PdfObject getObject(int num)
	{
		if(tables_ is null || tables_.length == 0) {
			throw new Error("PdfDocument not loaded.");
		}

		if(num >= tables_.length || tables_[num] is null) {
			throw new Error("expected object no");
		}

		auto obj = tables_[num].obj;
		if(obj !is null) {
			return obj;
		}

		if(tables_[num].type != 'n') {
			if(tables_[num].type == 'o') {
				// decode object stream
				getObject(cast(int)tables_[num].ofs);
				return getObject(num);
			}
			return null;
		}

		reader_.seek(tables_[num].ofs);
		int onum, ogen;
		size_t ofs_stm;
		if(tables_[num] is null) {
			tables_[num] = new XRefTable;
		}
		obj = parseIndirectObject(onum, ogen, ofs_stm);
		tables_[num].obj = obj;
		tables_[num].streamOnFS = ofs_stm;
		if(obj.kind == PdfObjKind.PDF_DICT && obj.objType == "ObjStm") {
			auto stmDict = cast(PdfDictionary)obj;
			auto stm = openStreamWithOffset(stmDict, onum, ogen, ofs_stm);

			auto firstObj = stmDict.getValue("First");
			if(firstObj is null || firstObj.kind != PdfObjKind.PDF_INT) {
				throw new Error("cannot recognize First Entry in ObjStm (%d %d R)".format(onum, ogen));
			}
			auto first = firstObj.value!int;

			auto NObj = stmDict.getValue("N");
			if(NObj is null || NObj.kind != PdfObjKind.PDF_INT) {
				throw new Error("cannot recognize N Entry in ObjStm (%d %d R)".format(onum, ogen));
			}
			auto N = NObj.value!int;

			auto rr = new MemoryReader(stm);
			auto lex = new PdfLexer(rr);

			int stmnums[];
			while(lex.next() == PdfToken.PDF_TOK_INT)
			{
				stmnums ~= to!int(lex.tokenStr);
			}

			for(int i = 0; i < N; ++i) {
				rr.seek(stmnums[(i << 1) + 1] + first);
				tables_[stmnums[i << 1]].obj = parseObjectInternal(lex, rr, stmnums[i << 1], 0, ofs_stm, true);
				tables_[stmnums[i << 1]].streamOnFS = ofs_stm;
			}
		}

		return tables_[num].obj;
	}

	ubyte[] getStream(int num)
	{
		if(tables_ is null || tables_.length == 0) {
			throw new Error("PdfDocument not loaded.");
		}

		if(num >= tables_.length || tables_[num] is null) {
			throw new Error("expected object no");
		}

		if(tables_[num] !is null && tables_[num].type != 'n') {
			if(tables_[num].type == 'o') {
				return getStream(cast(int)tables_[num].ofs);
			}
			return null;
		}

		auto trg = tables_[num];
		if(trg.streamOnFS == 0) {
			return null;
		}
		if(trg.stmBuff !is null) {
			return trg.stmBuff;
		}
		PdfDictionary dict;
		if(trg.obj is null) {
			auto obj = getObject(num);
			if(obj.kind != PdfObjKind.PDF_DICT) {
				return null;
			}
			dict = cast(PdfDictionary)obj;
		}
		else {
			if(trg.obj.kind != PdfObjKind.PDF_DICT) {
				return null;
			}
			dict = cast(PdfDictionary)trg.obj;
		}
		auto stm = openStreamWithOffset(dict, num, trg.gen, trg.streamOnFS);
		trg.stmBuff = stm;

		return stm;
	}

	void loadVersion()
	{
		auto ln = cast(string)reader_.readln();
		if(ln.indexOf("%PDF-") != 0) {
			throw new Error("cannot recognize version marker");
		}
		version_ = to!int(ln[5] - '0') * 10 + to!int(ln[7] - '0');
	}

	void readStartXRef()
	{
		size_t t, n;

		t = std.algorithm.max(0, reader_.length - 1024);
		reader_.seek(t);

		while(!reader_.eof) {
			auto ln = cast(string)reader_.readln();
			if(ln.indexOf("startxref") == 0) {
				ln = cast(string)reader_.readln;
				startxref_ = std.conv.parse!size_t(ln);

				return;
			}
		}
	}

	PdfObject readXRef(size_t ofs)
	{
		reader_.seek(ofs);
		while(isWhite(reader_.peek())) {
			reader_.readNext();
		}
		auto c = reader_.peek;
		PdfObject ret;
		if(c == 'x') {
			ret = readOldXRef();
		}
		else if('0' <= c && c <= '9') {
			ret = readCompressedXRef();
		}
		else {
			throw new Error("cannot recognize xref format %c".format(c));
		}
		return ret;
	}

	PdfDictionary readTrailer()
	{
		reader_.seek(startxref_);
		while(PdfLexer.isWhite(reader_.peek)) {
			reader_.readNext();
		}
		PdfDictionary ret;
		auto c = reader_.peek;
		if(c == 'x') {
			ret = cast(PdfDictionary)readOldXRef();
		}
		else if('0' <= c && c <= '9') {
			ret = cast(PdfDictionary)readCompressedXRef();
		}
		else {
			throw new Error("cannot recognize xref format %c".format(c));
		}
		return ret;
	}

	private PdfObject parseObjectInternal(PdfLexer lex, MemoryReader rd, int num, int gen, ref size_t streamOffsets, bool isObjStm)
	{
		PdfObject obj = null;		// MEMO:returnするオブジェクトは頭で宣言が必要！！
		bool skip = false;
		int a, b;
		auto tok = lex.next();
		switch(tok) {
			case PdfToken.PDF_TOK_OPEN_ARRAY:
				obj = new PdfArray();
				obj.parse(lex);
				break;

			case PdfToken.PDF_TOK_OPEN_DICT:
				obj = new PdfDictionary();
				obj.parse(lex);
				break;

			case PdfToken.PDF_TOK_NAME:
			case PdfToken.PDF_TOK_STRING:
				obj = new PdfString();
				obj.parse(lex);
				break;

			case PdfToken.PDF_TOK_REAL:
				obj = new PdfPrimitive(to!float(lex.tokenStr));
				break;

			case PdfToken.PDF_TOK_TRUE:
			case PdfToken.PDF_TOK_FALSE:
				obj = new PdfPrimitive(to!bool(lex.tokenStr));
				break;

			case PdfToken.PDF_TOK_NULL:
				obj = new PdfNull();
				break;

			case PdfToken.PDF_TOK_INT:
				a = to!int(lex.tokenStr);
				tok = lex.next();

				if(tok == PdfToken.PDF_TOK_STREAM || tok == PdfToken.PDF_TOK_ENDOBJ) {
					obj = new PdfPrimitive(a);
					skip = true;
					break;
				}
				if(tok == PdfToken.PDF_TOK_INT) {
					b = to!int(lex.tokenStr);
					tok = lex.next();
					if(tok == PdfToken.PDF_TOK_R) {
						obj = new PdfIndirect(a, b);
						break;
					}
				}
				throw new Error("expected 'R' keyword (%d %d R)".format(num, gen));

			case PdfToken.PDF_TOK_ENDOBJ:
				obj = new PdfNull();
				skip = true;
				break;

			default:
				throw new Error("syntax error in object (%d %d R)".format(num, gen));
		}

		if(!skip) {
			try {
				tok = lex.next();
			}
			catch(Throwable tw) {
				new Error("cannot parse indirect object (%d %d R) -- internal msg[%s]".format(num, gen, tw.msg));
			}
		}

		if(tok == PdfToken.PDF_TOK_STREAM) {
			ubyte c = rd.readByte();
			while(c == ' ') {
				c = rd.readByte();
			}
			if(c == '\r') {
				c = rd.peek();
				if(c != '\n') {
					"line feed missing after stream begin marker (%d %d R)".format(num, gen).writeln;
				}
				else {
					rd.readByte();
				}
			}
			streamOffsets = rd.position;
		}
		else if(tok == PdfToken.PDF_TOK_ENDOBJ) {
			streamOffsets = 0;
		}
		else {
			if(isObjStm == false) {
				"expected 'endobj' or 'stream' keyword (%d %d R)".format(num, gen).writeln;
			}
			streamOffsets = 0;
		}
		obj.objno = num;

		return obj;
	}

	private PdfObject parseIndirectObject(PdfLexer lex, MemoryReader rd, ref int onum, ref int ogen, ref size_t streamOffsets)
	{
		PdfObject obj = null;		// MEMO:returnするオブジェクトは頭で宣言が必要！！
		auto tok = lex.next();
		if(tok != PdfToken.PDF_TOK_INT) {
			throw new Error("expected object number.");
		}
		auto num = to!int(lex.tokenStr);

		tok = lex.next();
		if(tok != PdfToken.PDF_TOK_INT) {
			throw new Error("expected generation number (%d ? obj)".format(num));
		}
		auto gen = to!int(lex.tokenStr);

		tok = lex.next();
		if(tok != PdfToken.PDF_TOK_OBJ) {
			throw new Error("expected 'obj' keyword (%d %d ?)".format(num, gen));
		}

		return parseObjectInternal(lex, rd, num, gen, streamOffsets, false);
	}

	private PdfObject parseIndirectObject(ref int onum, ref int ogen, ref size_t streamOffsets)
	{
		return parseIndirectObject(lexer_, reader_, onum, ogen, streamOffsets);
	}

	private ubyte[] openStreamWithOffset(PdfDictionary stmobj, int num, int gen, size_t offset)
	{
		if(offset == 0) {
			throw new Error("object is not a stream");
		}

		auto filterObj = stmobj.getValue(["Filter", "F"]);
		auto params = cast(PdfDictionary)stmobj.getValue(["DecodeParms", "DP"]);

		if(num > 0 && tables_ !is null && num < tables_.length && tables_[num].stmBuff !is null) {
			return tables_[num].stmBuff;
		}
		auto lenobj = stmobj.getValue("Length");
		int stmlen = 0;
		if(lenobj.kind == PdfObjKind.PDF_INT) {
			stmlen = stmobj.getValue("Length").value!int;
		}
		else if(lenobj.kind == PdfObjKind.PDF_INDIRECT) {
			auto lenno = lenobj.value!(int[])[0];
			auto llobj = getObject(lenno);
			stmlen = llobj.value!int;
		}
		else {
			throw new Error("expected Length (%d %d R)".format(num, gen));
		}
		auto stm = reader.slice(offset,offset + stmlen);

		if(filterObj is null) {
			return stm;
		}

		string filters[];
		if(filterObj.kind == PdfObjKind.PDF_NAME) {
			filters ~= filterObj.value!string;
		}
		else if(filterObj.kind == PdfObjKind.PDF_ARRAY) {
			foreach(filter; filterObj.value!(PdfObject[])) {
				filters ~= filter.value!string;
			}
		}
		else {
			throw new Error("expected Filters in object (%d %d R)".format(num, gen));
		}
		PdfDecoder[] decoders;
		foreach(idx, flt; filters) {
			auto dec = PdfDecoder.PdfDecoder.create(flt, stmobj);
			if(decoders.length > 0) {
				decoders[idx - 1].next = dec;
			}
			decoders ~= dec;
		}
		auto xtbl = decoders[0].decode(stm);

		int predictor = 1;
		if(params !is null) {
			auto predObj = params.getValue("Predictor");
			if(predObj !is null) {
				predictor = predObj.value!int;
			}
		}
		if(predictor <= 1) {
			return xtbl;
		}
		int columns = 1;
		auto colObj = params.getValue("Columns");
		if(colObj !is null) {
			columns = colObj.value!int;
		}
		int bpc  = 8, colors = 1;
		int stride = (bpc * colors * columns + 7) / 8;
		int bpp = (bpc * colors + 7) / 8;



		// ★★★超暫定(predictor 処理)
		ubyte[] dst;
		auto ds = new MemoryReader(xtbl);
		auto prev = new ubyte[columns];
		auto rows = new ubyte[columns];
		size_t rowpos = rows.length;
		size_t count = xtbl.length;
		int ret = 0;
		while(ret < xtbl.length) {
			if(rowpos >= rows.length) {
				ds.readByte();
				/*
				if(ds.readByte() != 2) {
				throw new Error("unknown predictor type");
				}
				*/
				for(int i = 0; i < prev.length; ++i) {
					prev[i] = rows[i];
				}
				int len = 0;
				for(; len < rows.length; ++len) {
					rows[len] = ds.readByte();
					if(ds.eof) {
						break;
					}
				}
				if((len + 1) < rows.length) {
					break;
				}
				for(int i = 0; i < rows.length; ++i) {
					rows[i] += prev[i];
				}
				rowpos = 0;
			}
			size_t rlen = (count - ret) > (rows.length - rowpos) ? rows.length - rowpos : count - ret;
			dst ~= rows[rowpos..(rowpos + rlen)];
			ret += rlen;
			rowpos += rlen;
		}

		return dst;
	}

	private PdfObject readCompressedXRef()
	{
		int num, gen;
		size_t ofsStrm;
		PdfDictionary trailer;
		try {
			auto ofs = reader.position;
			trailer = cast(PdfDictionary)parseIndirectObject(num, gen, ofsStrm);

			if(num > tables_.length) {
				tables_.length = num + 1;
			}
			tables_[num] = new XRefTable;
			tables_[num].ofs = ofs;
			tables_[num].gen = gen;
			tables_[num].obj = trailer;
			tables_[num].streamOnFS = ofsStrm;
			tables_[num].type = 'n';
		}
		catch(Throwable tw) {
			new Error("cannot parse trailer (compressed) -- inner msg[%s]".format(tw.msg));
		}
		auto obj = trailer.getValue("Size");
		if(obj is null || obj.kind != PdfObjKind.PDF_INT) {
			new Error("xref stream missing Size entry (%d %d R)".format(num, gen));
		}
		int size = obj.value!int;
		if(size > tables_.length) {
			tables_.length = size;
		}

		obj = trailer.getValue("W");
		if(obj is null || obj.kind != PdfObjKind.PDF_ARRAY) {
			new Error("xref stream missing W entry (%d %d R)".format(num, gen));
		}
		int w0 = obj.value!(PdfObject[])[0].value!int;
		if(w0 < 0) {
			"xref stream objects have corrupt type".writeln;
		}
		int w1 = obj.value!(PdfObject[])[1].value!int;
		if(w1 < 0) {
			"xref stream objects have corrupt offset".writeln;
		}
		int w2 = obj.value!(PdfObject[])[2].value!int;
		if(w2 < 0) {
			"xref stream objects have corrupt generation".writeln;
		}

		w0 = w0 < 0 ? 0 : w0;
		w1 = w1 < 0 ? 0 : w1;
		w2 = w2 < 0 ? 0 : w2;

		auto index = trailer.getValue("Index");

		auto stm = openStreamWithOffset(trailer, num, gen, ofsStrm);
		auto xtblReader = new PdfStream.MemoryReader(stm);

		auto readSection = (XRefTable[] tbls, MemoryReader rr, int i0, int i1, int w0, int w1, int w2)
		{
			for(int i = i0; i < i0 + i1; ++i) {
				int a = 0, b = 0, c = 0;

				if(rr.eof) {
					throw new Error("truncated xref stream@%s:%d".format(__FILE__, __LINE__));
				}

				for(int n = 0; n < w0; n++) {
					a = (a << 8) + rr.readByte();
				}
				for(int n = 0; n < w1; n++) {
					b = (b << 8) + rr.readByte();
				}
				for(int n = 0; n < w2; n++) {
					c = (c << 8) + rr.readByte();
				}

				if(tbls[i] is null) {
					tbls[i] = new XRefTable;
				}
				if (!tbls[i].type) {
					int t = w0 ? a : 1;
					tbls[i].type = t == 0 ? 'f' : t == 1 ? 'n' : t == 2 ? 'o' : 0;
					tbls[i].ofs = w1 ? b : 0;
					tbls[i].gen = w2 ? c : 0;
				}

			}
		};

		if(index is null) {
			readSection(tables_, xtblReader, 0, size, w0, w1, w2);
		}
		else {
			if(index.kind != PdfObjKind.PDF_ARRAY) {
				throw new Error("Index objects is not array");
			}
			auto idxarray = index.value!(PdfObject[]);

			for(int t = 0; t < idxarray.length; t += 2) {
				int i0 = idxarray[t + 0].value!int;
				int i1 = idxarray[t + 1].value!int;

				readSection(tables_, xtblReader, i0, i1, w0, w1, w2);
			}
		}

		return trailer;
	}

	private PdfObject readOldXRef()
	{
		auto ln = cast(string)reader_.readln();
		if(ln.indexOf("xref") != 0) {
			throw new Error("cannot find xref marker");
		}
		while(true) {
			auto c = reader_.peek();
			if (!(c >= '0' && c <= '9')) {
				break;
			}

			ln = cast(string)reader_.readln();
			auto xrefln = split(ln);
			int ofs = to!int(xrefln[0]);
			int len = to!int(xrefln[1]);

			if(ofs + len > tables_.length) {
				tables_.length = ofs + len;
			}
			for(int i = ofs; i < ofs + len; ++i) {
				ln = cast(string)reader_.readln();
				if(ln.length != 19) {
					throw new Error("cannot read xref table");
				}
				xrefln = split(ln);

				tables_[i] = new XRefTable;
				tables_[i].ofs = to!int(xrefln[0]);
				tables_[i].gen = to!int(xrefln[1]);
				auto ch = xrefln[2][0];
				if(ch != 'f' && ch != 'n' && ch != 'o') {
					throw new Error("unexpected xref type: %#x (%d %d R)".format(ch, i, tables_[i].gen));
				}
				tables_[i].type = xrefln[2][0];
			}
		}
		auto tok = lexer_.next();
		if(tok != PdfToken.PDF_TOK_TRAILER) {
			throw new Error("expected trailer marker");
		}
		tok = lexer_.next();
		if(tok != PdfToken.PDF_TOK_OPEN_DICT) {
			throw new Error("expected trailer dictionary");
		}
		auto trailer = new PdfDictionary();
		trailer.parse(this.lexer);

		return trailer;
	}
}
