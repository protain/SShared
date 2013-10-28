module PdfLexer;

import std.stdio;
import std.conv;
import std.string;
import std.file;
import std.array;

import PdfStream;
import PdfObjects;

enum PdfToken : char
{
	PDF_TOK_ERROR = 0,
	PDF_TOK_EOF = 'E',
	PDF_TOK_OPEN_ARRAY = 'a',
	PDF_TOK_CLOSE_ARRAY = 'A',
	PDF_TOK_OPEN_DICT = 'd',
	PDF_TOK_CLOSE_DICT = 'D',
	PDF_TOK_OPEN_BRACE = 'b',
	PDF_TOK_CLOSE_BRACE = 'B',
	PDF_TOK_NAME = 'n',
	PDF_TOK_INT = 'i',
	PDF_TOK_REAL = 'r',
	PDF_TOK_STRING = 's',
	PDF_TOK_KEYWORD = 'k',
	PDF_TOK_R = 'R',
	PDF_TOK_TRUE = 't',
	PDF_TOK_FALSE = 'f',
	PDF_TOK_NULL = 'N',
	PDF_TOK_OBJ = 'o',
	PDF_TOK_ENDOBJ = 'O',
	PDF_TOK_STREAM = 'm',
	PDF_TOK_ENDSTREAM = 'M',
	PDF_TOK_XREF = 'X',
	PDF_TOK_TRAILER = 'T',
	PDF_TOK_STARTXREF = 'x',
	PDF_NUM_TOKENS = 'Z'
}

static bool isWhite(ubyte ch)
{
	return
		ch == '\000' || ch == '\011' || ch == '\012' ||
		ch == '\014' || ch == '\015' || ch == '\040';
}

static bool isDelim(ubyte ch)
{
	return
		ch == '(' || ch == ')' || ch == '<' || ch == '>' ||
		ch == '[' || ch == ']' || ch == '{' || ch == '}' ||
		ch == '/' || ch == '%';
}

static bool isDigit(ubyte ch)
{
	switch(ch) {
		case '0': case '1': case '2': case '3': case '4':
		case '5': case '6': case '7': case '8': case '9':
			return true;
		default:
			return false;
	}
}

static bool isNumber(ubyte ch)
{
	switch(ch) {
		case '+': case '-': case '.':
		case '0': case '1': case '2': case '3': case '4':
		case '5': case '6': case '7': case '8': case '9':
			return true;
		default:
			return false;
	}
}

static bool isHex(ubyte ch)
{
	switch(ch) {
		case '0': case '1': case '2': case '3': case '4':
		case '5': case '6': case '7': case '8': case '9':
		case 'a': case 'b': case 'c': case 'd': case 'e': case 'f':
		case 'A': case 'B': case 'C': case 'D': case 'E': case 'F':
			return true;

		default:
			return false;
	}
}

static int unhex(ubyte ch)
{
	if (ch >= '0' && ch <= '9') return ch - '0';
	if (ch >= 'A' && ch <= 'F') return ch - 'A' + 0xA;
	if (ch >= 'a' && ch <= 'f') return ch - 'a' + 0xA;
	return 0;
}


class PdfLexer
{
	ubyte[] lexBuf_;
	MemoryReader reader_;
	PdfToken token_;

public:
	@property MemoryReader reader()
	{
		return reader_;
	}

private:

	PdfToken tokenFromKeyword()
	{
		if(lexBuf_.length == 0) {
			return PdfToken.PDF_TOK_ERROR;
		}
		auto buf = cast(string)lexBuf_;
		switch(buf[0]) {
		case 'R':
			if(buf == "R") return PdfToken.PDF_TOK_R;
			break;
		case 't':
			if(buf == "true") return PdfToken.PDF_TOK_TRUE;
			if(buf == "trailer") return PdfToken.PDF_TOK_TRAILER;
			break;
		case 'f':
			if(buf == "false") return PdfToken.PDF_TOK_FALSE;
			break;
		case 'n':
			if(buf == "null") return PdfToken.PDF_TOK_NULL;
			break;
		case 'o':
			if(buf == "obj") return PdfToken.PDF_TOK_OBJ;
			break;
		case 'e':
			if(buf == "endobj") return PdfToken.PDF_TOK_ENDOBJ;
			if(buf == "endstream") return PdfToken.PDF_TOK_ENDSTREAM;
			break;
		case 's':
			if(buf == "stream") return PdfToken.PDF_TOK_STREAM;
			if(buf == "startxref") return PdfToken.PDF_TOK_STARTXREF;
			break;
		case 'x':
			if(buf == "xref") return PdfToken.PDF_TOK_XREF;
			break;
		default:
			break;
		}

		return PdfToken.PDF_TOK_KEYWORD;
	}

	void eatWhite()
	{
		ubyte c;
		do {
			c = reader_.readByte();
		} while((c <= 32) && isWhite(c) && !reader_.eof);
		if(!reader_.eof) {
			reader_.previous();
		}
	}

	void eatComment()
	{
		ubyte c;
		do {
			c = reader_.readByte();
		} while((c != '\012') && (c != '\015') && !reader_.eof);
	}

	PdfToken processName()
	{
		lexBuf_.length = 0;
		while(true) {
			if(reader_.eof) {
				break;
			}
			auto c = reader_.readByte();
			if(isWhite(c) || isDelim(c)) {
				reader_.previous();
				break;
			}
			else if(c == '#') {
				int d = 0;
				c = reader_.readByte();
				if(isHex(c)) {
					d = unhex(c);
				}
				else {
					reader_.previous();
				}
				if(reader_.eof) {
					break;
				}
				c = reader_.readByte();
				if(isHex(c)) {
					d = cast(ubyte)(d << 4) | (unhex(c));
				}
				else {
					reader_.previous();
				}
				if(reader_.eof) {
					lexBuf_ ~= cast(ubyte)d;
					break;
				}
				lexBuf_ ~= cast(ubyte)(d);
			}
			else {
				lexBuf_ ~= c;
			}
		}
		return PdfToken.PDF_TOK_NAME;
	}

	PdfToken processHexString()
	{
		lexBuf_.length = 0;
		ubyte a = 0;
		bool x = false;

		while(true) {
			if(reader_.eof) {
				return PdfToken.PDF_TOK_STRING;
			}
			auto c = reader_.readByte();
			if(isWhite(c)) {
				break;
			}
			else if(isHex(c)) {
				if(x) {
					lexBuf_ ~=  cast(ubyte)(a * 16 + unhex(c));
					x = !x;
				}
				else {
					a = cast(ubyte)unhex(c);
					x = !x;
				}
			}
			else if(c == '>') {
				return PdfToken.PDF_TOK_STRING;
			}
			else {
				//
				writeln("ignoring invalid character in hex string: '%c'".format(cast(char)c));
			}
		}
		return PdfToken.PDF_TOK_STRING;
	}

	PdfToken processNumber()
	{
		lexBuf_.length = 0;
		while(true) {
			if(reader_.eof) {
				break;
			}
			auto c = reader_.readByte();
			if(isNumber(c)) {
				lexBuf_ ~= c;
			}
			else {
				reader_.previous();
				break;
			}
		}
		auto buf = cast(string)lexBuf_;
		return (buf.indexOf(".") >= 0) ?
			PdfToken.PDF_TOK_REAL : PdfToken.PDF_TOK_INT;
	}

	PdfToken processString()
	{
		lexBuf_.length = 0;
		int bal = 1;
		while(true) {
			if(reader_.eof) {
				break;
			}
			auto c = reader_.readByte();
			switch(c) {
				case '(':
					bal++;
					lexBuf_ ~= c;
					break;
				case ')':
					bal--;
					if(bal == 0) {
						return PdfToken.PDF_TOK_STRING;
					}
					lexBuf_ ~= c;
					break;

				case '\\':
					if(reader_.eof) {
						return PdfToken.PDF_TOK_STRING;
					}
					c = reader_.readByte();
					switch(c) {
						case 'n':
							lexBuf_ ~= '\n';
							break;
						case 'r':
							lexBuf_ ~= '\r';
							break;
						case 't':
							lexBuf_ ~= '\t';
							break;
						case 'b':
							lexBuf_ ~= '\b';
							break;
						case 'f':
							lexBuf_ ~= '\f';
							break;
						case '(':
							lexBuf_ ~= '(';
							break;
						case ')':
							lexBuf_ ~= ')';
							break;
						case '\\':
							lexBuf_ ~= '\\';
							break;
						case '\n':
							break;
						case '\r':
							c = reader_.readByte();
							if(c != '\n' && !reader_.eof) {
								reader_.previous();
							}
							break;

						default:
							if(isDigit(c)) {
								int oct = c - '0';
								if(c >= '0' && c <= '9') {
									oct = oct * 8 + (c - '0');
									c = reader_.readByte();
									if(c >= '0' && c <= '9') {
										oct = oct * 8 + (c - '0');
									}
									else if(!reader_.eof) {
										reader_.previous();
									}
								}
								else if(!reader_.eof) {
									reader_.previous();
								}
								lexBuf_ ~= cast(ubyte)oct;
							}
							else {
								lexBuf_ ~= c;
							}
							break;
					}
					break;

				default:
					lexBuf_ ~= c;
					break;
			}

		}

		return PdfToken.PDF_TOK_STRING;
	}

public:
	@property ubyte[] tokenValue()
	{
		return lexBuf_;
	}

	@property string tokenStr()
	{
		return cast(string)lexBuf_;
	}

	@property PdfToken currntToken()
	{
		return token_;
	}

	this(MemoryReader reader)
	{
		reader_ = reader;
	}

	PdfToken next()
	{
		while(true) {
			if(reader_.eof) {
				token_ = PdfToken.PDF_TOK_EOF;
				break;
			}
			auto c = reader_.readByte();
			switch(c) {
				case '\000': case '\011': case '\012':
				case '\014': case '\015': case '\040':
					eatWhite();
					break;

				case '%':
					eatComment();
					break;

				case '/':
					token_ = processName();
					return token_;

				case '(':
					token_ = processString();
					return token_;
				case ')':
					writeln("lexical error (unexpected ')')");
					continue;

				case '<':
					c = reader_.readByte();
					if(c == '<') {
						token_ = PdfToken.PDF_TOK_OPEN_DICT;
						return token_;
					}
					else {
						reader_.previous();
						token_ = processHexString();
						return token_;
					}

				case '>':
					c = reader_.readByte();
					if(c == '>') {
						token_ = PdfToken.PDF_TOK_CLOSE_DICT;
						return token_;
					}
					writeln("lexical error (unexpected '>')");
					continue;

				case '[':
					token_ = PdfToken.PDF_TOK_OPEN_ARRAY;
					return token_;
				case ']':
					token_ = PdfToken.PDF_TOK_CLOSE_ARRAY;
					return token_;
				case '{':
					token_ = PdfToken.PDF_TOK_OPEN_BRACE;
					return token_;
				case '}':
					token_ = PdfToken.PDF_TOK_CLOSE_BRACE;
					return token_;

				default:
					if(isNumber(c) || c == '.') {
						reader_.previous();
						token_ = processNumber();
						return token_;
					}
					else {
						reader_.previous();
						processName();
						token_ = tokenFromKeyword();
						return token_;
					}
			}
		}
		return token_;	// mey be eof;
	}

}
