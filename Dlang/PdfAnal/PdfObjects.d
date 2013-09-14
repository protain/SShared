module PdfObjects;

import std.stdio;
import std.conv;
import std.string;
import std.file;
import std.array;

import PdfLexer;
import PdfStream;
import PdfDocument;

enum PdfObjKind : char
{
	PDF_NULL = 0,
	PDF_BOOL = 'b',
	PDF_INT = 'i',
	PDF_REAL = 'f',
	PDF_STRING = 's',
	PDF_NAME = 'n',
	PDF_ARRAY = 'a',
	PDF_DICT = 'd',
	PDF_INDIRECT = 'r'
}

PdfObject dictGets(PdfObject obj, string key)
{
	if(obj.kind != PdfObjKind.PDF_DICT) {
		return null;
	}
	auto dict = cast(PdfDictionary)obj;
	return dict.getValue(key);
}

PdfObject dictGets(PdfObject obj, string[] keys)
{
	if(obj.kind != PdfObjKind.PDF_DICT) {
		return null;
	}
	auto dict = cast(PdfDictionary)obj;
	return dict.getValue(keys);
}

PdfObject arrayGets(PdfObject obj, size_t idx)
{
	if(obj.kind != PdfObjKind.PDF_ARRAY) {
		return null;
	}
	auto ary = obj.value!(PdfObject[]);
	return ary[idx];
}

void dictPuts(PdfObject obj, string key, PdfObject value)
{
	if(obj.kind != PdfObjKind.PDF_DICT) {
		return;
	}
	auto val = obj.value!(PdfObject[string]);
	val[key] = value;
}

int arrayLen(PdfObject obj)
{
	if(obj.kind != PdfObjKind.PDF_ARRAY) {
		return -1;
	}
	auto ary = cast(PdfArray)obj;
	return cast(int)(ary.value!(PdfObject[]).length);
}

abstract class PdfObject
{
protected:
	V v;
	union V
	{
		PdfObject[] array_;
		PdfObject[string] keyvalue_;
		string strValue_;
		int[] ind_;
		int i_;
		float f_;
		bool b_;
	}
	int objno_;
	int refs_;
	char marked_;

	Object getValueInternal()
	{
		return null;
	}

public:
	this() { refs_ = 1; marked_ = 0; v.array_ = null; v.f_ = 0f; objno_ = -1; }

	@property int objno() { return objno_; }
	@property void objno(int num) { objno_ = num; }
	@property int refs() { return refs_; }
	@property char marked() { return marked_; }
	@property PdfObjKind kind();
	void parse(PdfLexer lex);
	@property T value(T)()
	{
		static if(__traits(isScalar, T)) {
			static if(is(T : int) || is(T : size_t)) {
				assert(kind == PdfObjKind.PDF_INT || kind == PdfObjKind.PDF_REAL);
				if(kind == PdfObjKind.PDF_INT) {
					return cast(T)v.i_;
				}
				else {
					return to!int(v.f_);
				}
			}
			else static if(is(T : float)) {
				assert(kind == PdfObjKind.PDF_INT || kind == PdfObjKind.PDF_REAL);
				if(kind == PdfObjKind.PDF_INT) {
					return to!T(v.i_);
				}
				else {
					return cast(T)v.f_;
				}
			}
			else static if(is(T : bool)) {
				assert(kind == PdfObjKind.PDF_BOOL);
				return cast(T)v.b_;
			}
			else {
				assert(false);
			}
		}
		else {
			static if(is(T : PdfObject[])) {
				assert(kind == PdfObjKind.PDF_ARRAY);
				return cast(T)v.array_;
			}
			else static if(is(T : immutable(ubyte[]))) {
				assert(kind == PdfObjKind.PDF_STRING || kind == PdfObjKind.PDF_NAME);
				return cast(T)v.strValue_;
			}
			else static if(is(T : PdfObject[string])) {
				assert(kind == PdfObjKind.PDF_DICT);
				return cast(T)v.keyvalue_;
			}
			else static if(is(T : string)) {
				assert(kind == PdfObjKind.PDF_STRING || kind == PdfObjKind.PDF_NAME);
				return cast(T)v.strValue_;
			}
			else static if(is(T : int[])) {
				assert(kind == PdfObjKind.PDF_INDIRECT);
				return cast(T)v.ind_;
			}
			else {
				return cast(T)getValueInternal();
			}
		}
	}

	@property string objType()
	{
		if(kind != PdfObjKind.PDF_DICT) {
			return "";
		}
		auto tyobj = (cast(PdfDictionary)this).getValue("Type");
		if(tyobj is null) {
			return "";
		}
		return tyobj.value!string;
	}
}

class PdfNull : PdfObject
{
public:
	override @property PdfObjKind kind()
	{
		return PdfObjKind.PDF_NULL;
	}

	override void parse(PdfLexer lex)
	{
		if(lex.currntToken != PdfToken.PDF_TOK_NULL) {
			throw new Error("invalid token type in PdfNull");
		}
	}
	override string toString()
	{
		return "null";
	}

}

class PdfArray : PdfObject
{
public:
	override @property PdfObjKind kind()
	{
		return PdfObjKind.PDF_ARRAY;
	}

	override void parse(PdfLexer lex)
	{
		if(lex.currntToken != PdfToken.PDF_TOK_OPEN_ARRAY) {
			throw new Error("invalid token in PdfArray");
		}
		// skip....
		int n = 0;
		int a = 0, b = 0;
		PdfObject obj;

		while(true) {
			auto tok = lex.next();

			if(tok != PdfToken.PDF_TOK_INT && tok != PdfToken.PDF_TOK_R) {
				if(n > 0) {
					obj = new PdfPrimitive(a);
					v.array_ ~= obj;
				}
				if(n > 1) {
					obj = new PdfPrimitive(b);
					v.array_ ~= obj;
				}
				n = 0;
			}

			if(tok == PdfToken.PDF_TOK_INT && n == 2) {
				obj = new PdfPrimitive(a);
				v.array_ ~= obj;
				a = b;
				--n;
			}
			switch(tok) {
			case PdfToken.PDF_TOK_CLOSE_ARRAY:
				return;

			case PdfToken.PDF_TOK_INT:
				if(n == 0) {
					a = to!int(lex.tokenStr);
				}
				if(n == 1) {
					b = to!int(lex.tokenStr);
				}
				++n;
				break;

			case PdfToken.PDF_TOK_R:
				if(n != 2) {
					throw new Error("cannot parse indirect reference in array");
				}
				obj = new PdfIndirect(a, b);
				v.array_ ~= obj;
				n = 0;
				break;

			case PdfToken.PDF_TOK_OPEN_ARRAY:
				obj = new PdfArray();
				obj.parse(lex);
				v.array_ ~= obj;
				break;

			case PdfToken.PDF_TOK_OPEN_DICT:
				obj = new PdfDictionary();
				obj.parse(lex);
				v.array_ ~= obj;
				break;

			case PdfToken.PDF_TOK_NAME:
			case PdfToken.PDF_TOK_STRING:
				obj = new PdfString();
				obj.parse(lex);
				v.array_ ~= obj;
				break;

			case PdfToken.PDF_TOK_REAL:
			case PdfToken.PDF_TOK_FALSE:
			case PdfToken.PDF_TOK_TRUE:
				obj = new PdfPrimitive();
				obj.parse(lex);
				v.array_ ~= obj;
				break;

			case PdfToken.PDF_TOK_NULL:
				obj = new PdfNull();
				v.array_ ~= obj;
				break;

			default:
				throw new Error("cannot parse token in array");
			}
		}
	}

	override string toString()
	{
		char[] buf;
		buf ~= "[";
		foreach(i, PdfObject obj; v.array_) {
			if(i != 0) {
				buf ~= ", ";
			}
			buf ~= obj.toString();
		}
		buf ~= "]";
		return cast(string)buf;
	}
}

class PdfPrimitive : PdfObject
{
	PdfObjKind kind_;

public:
	this() { }

	this(int i)
	{
		kind_ = PdfObjKind.PDF_INT;
		v.i_ = i;
	}

	this(bool b)
	{
		kind_ = PdfObjKind.PDF_BOOL;
		v.b_ = b;
	}

	this(float f)
	{
		kind_ = PdfObjKind.PDF_REAL;
		v.f_ = f;
	}

	override @property PdfObjKind kind()
	{
		return kind_;
	}

	override void parse(PdfLexer lex)
	{
		switch(lex.currntToken) {
			case PdfToken.PDF_TOK_REAL:
				kind_ = PdfObjKind.PDF_REAL;
				v.f_ = to!float(lex.tokenStr);
				break;
			case PdfToken.PDF_TOK_INT:
				kind_ = PdfObjKind.PDF_INT;
				v.i_ = to!int(lex.tokenStr);
				break;
			case PdfToken.PDF_TOK_FALSE:
			case PdfToken.PDF_TOK_TRUE:
				kind_ = PdfObjKind.PDF_BOOL;
				v.b_ = to!bool(lex.tokenStr);
				break;
			default:
				throw new Error("unknwon token in PdfPrimitive");
		}
	}

	override string toString()
	{
		switch(kind) {
		case PdfObjKind.PDF_BOOL:
			return to!string(v.b_);
		case PdfObjKind.PDF_INT:
			return to!string(v.i_);
		case PdfObjKind.PDF_REAL:
			return to!string(v.f_);
		default:
			throw new Error("unknown kind in PdfPrimitive");
		}
	}
}

//*/
class PdfString : PdfObject
{
	PdfObjKind kind_;
	bool isOnlyAscii_;
public:
	override @property PdfObjKind kind()
	{
		return kind_;
	}

	override @property T value(T = string)() if(T is string)
	{
		return cast(T)strValue_;
	}

	override void parse(PdfLexer lex)
	{
		auto tok = lex.currntToken;
		if(tok == PdfToken.PDF_TOK_STRING) {
			kind_ = PdfObjKind.PDF_STRING;
		}
		else if(tok == PdfToken.PDF_TOK_NAME) {
			kind_ = PdfObjKind.PDF_NAME;
		}
		else {
			throw new Error("unknown toke type in PdfString");
		}
		v.strValue_ = lex.tokenStr.idup;
		isOnlyAscii_ = true;
		foreach(c; v.strValue_) {
			if(c < 0x20 || c > 0x7e) {
				isOnlyAscii_ = false;
				break;
			}
		}
	}

	override string toString()
	{
		if(isOnlyAscii_) {
			return `"` ~ v.strValue_ ~ `"`;
		}
		else {
			char[] buf;
			buf ~= "[";
			foreach(i, c; v.strValue_) {
				if(i != 0) {
					buf ~= ", ";
				}
				buf ~= "%d".format(c);
			}
			buf ~= "]";
			return cast(string)buf;
		}
	}
}

class PdfIndirect : PdfObject
{
public:
	@property int num() { return v.ind_[0]; }
	@property int gen() { return v.ind_[1]; }

	this() { this(0, 0); }
	this(int num, int gen)
	{
		v.ind_ ~= num;
		v.ind_ ~= gen;
	}

	override @property PdfObjKind kind()
	{
		return PdfObjKind.PDF_INDIRECT;
	}

	override @property T value(T = int[2])()
	{
		return cast(T)([num_, gen_]);
	}

	override void parse(PdfLexer lex)
	{
		if(lex.currntToken !=  PdfToken.PDF_TOK_INT) {
			throw new Error("invalid token in PdfIndirect");
		}
		v.ind_[0] = to!int(lex.tokenStr);
		auto tok = lex.next();
		if(tok !=  PdfToken.PDF_TOK_INT) {
			throw new Error("invalid token in PdfIndirect");
		}
		v.ind_[1] = to!int(lex.tokenStr);
		tok = lex.next();
		if(tok != PdfToken.PDF_TOK_R) {
			throw new Error("invalid token in PdfIndirect");
		}
	}

	override string toString()
	{
		return `{"$Type":"R", "num":%d, "gen":%d}`.format(num, gen);
	}
}

class PdfDictionary : PdfObject
{
public:
	override @property PdfObjKind kind()
	{
		return PdfObjKind.PDF_DICT;
	}

	PdfObject getValue(string key)
	{
		PdfObject *obj = key in v.keyvalue_;
		return obj ? *obj : null;
	}

	PdfObject getValue(string[] keys)
	{
		foreach(k; keys) {
			auto o = getValue(k);
			if(o !is null) {
				return o;
			}
		}
		return null;
	}

	override void parse(PdfLexer lex)
	{
		if(lex.currntToken != PdfToken.PDF_TOK_OPEN_DICT) {
			throw new Error("invalid token in dict start");
		}

		while(true) {
			auto tok = lex.next();

		skip:
			if(tok == PdfToken.PDF_TOK_CLOSE_DICT) {
				break;
			}
			if(tok == PdfToken.PDF_TOK_KEYWORD && lex.tokenStr == "ID") {
				break;
			}
			if(tok != PdfToken.PDF_TOK_NAME) {
				throw new Error("invalid key in dict");
			}

			auto key = lex.tokenStr;
			PdfObject val;

			auto pos = lex.reader.position;
			tok = lex.next();

			//"token:%s".format(tok).writeln;

			switch(tok) {
				case PdfToken.PDF_TOK_OPEN_ARRAY:
					val = new PdfArray();
					val.parse(lex);
					break;
				case PdfToken.PDF_TOK_OPEN_DICT:
					val = new PdfDictionary();
					val.parse(lex);
					break;

				case PdfToken.PDF_TOK_NAME:
				case PdfToken.PDF_TOK_STRING:
					val = new PdfString();
					val.parse(lex);
					break;

				case PdfToken.PDF_TOK_FALSE:
				case PdfToken.PDF_TOK_TRUE:
				case PdfToken.PDF_TOK_REAL:
					val = new PdfPrimitive();
					val.parse(lex);
					break;

				case PdfToken.PDF_TOK_INT: {
					auto a = to!int(lex.tokenStr);
					tok = lex.next();
					if(tok == PdfToken.PDF_TOK_CLOSE_DICT || tok == PdfToken.PDF_TOK_NAME ||
					   (tok == PdfToken.PDF_TOK_KEYWORD && lex.tokenStr == "ID"))
					{
						v.keyvalue_[key] = new PdfPrimitive(a);
						goto skip;
					}
					if(tok == PdfToken.PDF_TOK_INT) {
						lex.reader.seek(pos);
						lex.next();
						val = new PdfIndirect();
						val.parse(lex);
						break;
					}
					throw new Error("invalid indirect reference in dict");
				}

				case PdfToken.PDF_TOK_NULL:
					val = new PdfNull();
					break;

				default:
					throw new Error("unknown token in dict");
			}

			//"%s:[%s]".format(key, val).writeln;

			v.keyvalue_[key] = val;
		}
	}

	override string toString()
	{
		char[] buf;
		buf ~= "{";
		foreach(ii, kk; v.keyvalue_.keys) {
			if(ii != 0) {
				buf ~= ", ";
			}
			buf ~= `"` ~ kk ~ `":` ~ v.keyvalue_[kk].toString();
		}
		buf ~= "}";
		return cast(string)buf;
	}
}
