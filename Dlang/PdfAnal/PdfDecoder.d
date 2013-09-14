module PdfDecoder;

import std.stdio;
import std.string;
import PdfObjects;
import PdfLexer;

abstract class PdfDecoder
{
	// next decoder.
	PdfDecoder next_;
public:
	static PdfDecoder create(string name, PdfObject obj)
	{
		PdfDecoder dec;
		switch(name) {
		case "ASCIIHexDecode", "AHx":
			dec = new AsciiHexDecoder;
			break;
		case "ASCII85Decode", "A85":
			dec = new Ascii85Decoder;
			break;
		case "CCITTFaxDecode", "CCF":
			dec = new FaxDecoder;
			break;
		case "DCTDecode", "DCT":
			dec = new DCTDecoder;
			break;
		case "FlateDecode", "Fl":
			dec = new FlateDecoder;
			break;
		default:
			throw new Error("unknown filter name(%s)".format(name));
		}
		dec.init(obj);
		return dec;
	}

	@property void next(PdfDecoder nxt) { next_ = nxt; }
	ubyte[] decode(ubyte[] src);
	void init(PdfObject obj) {}
}

class FlateDecoder : PdfDecoder
{
	override ubyte[] decode(ubyte[] stm)
	{
		import std.zlib;
		if(next_ is null) {
			return cast(ubyte[])(std.zlib.uncompress(stm));
		}
		else {
			return next_.decode(cast(ubyte[])(std.zlib.uncompress(stm)));
		}
	}
}

class DCTDecoder : PdfDecoder
{
	override ubyte[] decode(ubyte[] stm)
	{
		return stm;
	}
}

class AsciiHexDecoder : PdfDecoder
{
	override ubyte[] decode(ubyte[] stm)
	{
		return stm;
	}
}

class Ascii85Decoder : PdfDecoder
{
	immutable(int[]) pow85 =
	[
		85 * 85 * 85 * 85,
		85 * 85 * 85,
		85 * 85,
		85,
		1
	];

	override ubyte[] decode(ubyte[] stm)
	{
		ubyte[] dst;
		ubyte[4] decodeBlock;
		int count = 0;
		int tuple = 0;
		bool processChar = false;
		int asciiOffset = 33;

		foreach(idx, c; stm) {
			switch(c) {
			case 'z':
				if(count != 0) {
					throw new Error("character 'z' is invalid inside an ASCII85 block.");
				}
				dst ~= 0;
				dst ~= 0;
				dst ~= 0;
				dst ~= 0;
				processChar = false;
				break;
			case '\n', '\r', '\0', '\f', '\b', '\t':
				processChar = false;
				break;

			case '~':
				if(stm[idx + 1] != '>') {
					"bad eod marker in ASCII85".writeln;
				}
				goto eod;

			default:
				if(c < '!' || c > 'u') {
					throw new Error("bad character '%c' found in ASCII85 decoding.".format(c));
				}
				processChar = true;
				break;
			}
		
			if(processChar) {
				tuple += (cast(uint)(c - asciiOffset) * pow85[count]);
				count++;
				if(count == 5) {
					for (int i = 0; i < 4; i++) {
						dst ~= cast(ubyte)(tuple >> 24 - (i * 8));   
					}
					tuple = count = 0;
				}
			}
		}

eod:
		if(count != 0) {
			if(count == 1) {
				throw new Error("the last block of ASCII85 data cannot be a single byte.");
			}
			--count;
			tuple += pow85[count];
			for (int i = 0; i < count; i++) {
				dst ~= cast(ubyte)(tuple >> 24 - (i * 8));   
			}
		}
		if(next_ is null) {
			return dst;
		}
		else {
			return next_.decode(dst);
		}
	}
}

class LZWDecoder : PdfDecoder
{
	override ubyte[] decode(ubyte[] stm)
	{
		return stm;
	}
}

class FaxDecoder : PdfDecoder
{
	override ubyte[] decode(ubyte[] stm)
	{
		return stm;
	}
}

