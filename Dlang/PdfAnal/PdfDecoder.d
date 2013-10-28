module PdfDecoder;

import std.stdio;
import std.string;
import PdfObjects;
import PdfLexer;
import PdfStream;

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
		case "JPXDecode":
			dec =  new JPXDecoder;
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

class PredictDecoder : PdfDecoder
{
	int predictor_;
	int columns_;
	int stride_;
	int bpp_;
	int colors_;
	int bpc_;

	override void init(PdfObject params)
	{
		predictor_ = 1;
		if(params !is null) {
			auto predObj = params.dictGets("Predictor");
			if(predObj !is null) {
				predictor_ = predObj.value!int;
			}
		}
		if(predictor_ <= 1) {
			return;
		}
		if(predictor_ != 2 && predictor_ != 10 && predictor_ != 11 &&
		   predictor_ != 12 && predictor_ != 13 && predictor_ != 14 && predictor_ != 15)
		{
			throw new Error("expected Predictor (%d)".format(predictor_));
		}

		columns_ = 1;
		auto colObj = params.dictGets("Columns");
		if(colObj !is null) {
			columns_ = colObj.value!int;
		}
		bpc_ = 8;
		auto bpcObj = params.dictGets("BitsPerComponent");
		if(bpcObj !is null) {
			bpc_ = bpcObj.value!int;
		}
		colors_ = 1;
		auto colorObj = params.dictGets("Colors");
		if(colorObj !is null) {
			colors_ = colorObj.value!int;
		}
		stride_ = (bpc_ * colors_ * columns_ + 7) / 8;
		bpp_ = (bpc_ * colors_ + 7) / 8;

	}

	ubyte paeth(ubyte a, ubyte b, ubyte c)
	{
		import std.math;

		int ac = b - c, bc = a - c, abcc = ac + bc;
		int pa = cast(int)abs(ac);
		int pb = cast(int)abs(bc);
		int pc = cast(int)abs(abcc);
		return (pa <= pb && pa <= pc ? a : pb <= pc ? b : c) & 0xff;
	}

	override ubyte[] decode(ubyte[] stm)
	{
		if(predictor_ == 1) {
			return stm;
		}
		else if(predictor_ == 2) {
			ubyte[] dst;
			int pos = 0;

			for(int y = 0; y < (stm.length / stride_); ++y) {
				for(int x = bpp_; x < stride_; ++x) {
					int idx = stride_ * y + x;
					stm[idx] = (stm[idx] + stm[idx - bpp_]) & 0xff;
				}
			}
			return stm;

			/+
			auto ds = new MemoryReader(stm);
			try {
				while(!ds.eof) {
					if(pos >= stm.length) {
						break;
					}
					auto line = ds.slice(pos, pos + stride_);
					auto rows = new ubyte[stride_];

					int left[32] = 0;
					for(int i = 0; i < columns_; ++i) {
						for(int k = 0; k < colors_; ++k) {
							int a = 0;
							int xx = i * colors_ + k;
							// get component
							switch(bpc_) {
							case 1: a = (stm[xx >> 3] >> (7 - (xx & 7))) & 1; break;
							case 2: a = (stm[xx >> 2] >> ((3 - (xx & 3)) << 1)) & 3; break;
							case 4: a = (stm[xx >> 1] >> ((1 - (xx & 1)) << 2)) & 15; break;
							case 8: a = stm[xx]; break;
							case 16: a = (stm[xx << 1] << 8) + stm[(xx << 1) + 1]; break;
							default: a = 0; break;
							}
							int b = a + left[k];
							int c = b & ((1 << bpc_) - 1);
							// put component
							switch(bpc_) {
							case 1: rows[xx >> 3] |= c << (7 - (xx & 7)); break;
							case 2: rows[xx >> 2] |= c << ((3 - (xx & 3)) << 1); break;
							case 4: rows[xx >> 1] |= c << ((1 - (xx & 1)) << 2); break;
							case 8: rows[xx] = cast(ubyte)c; break;
							default: rows[xx << 1] = cast(ubyte)(c >> 8); rows[(xx << 1) + 1] = cast(ubyte)c; break;
							}
							left[k] = c;
						}
					}
					dst ~= rows;
					pos += stride_;
				}
			}
			catch(Throwable ee) {
				auto msg = ee.msg;
			}
			return dst;
			+/
		}
		else {
			ubyte[] dst;
			auto ds = new MemoryReader(stm);
			auto prev = new ubyte[columns_];
			auto rows = new ubyte[columns_];
			size_t rowpos = rows.length;
			size_t count = stm.length;
			int ret = 0;
			while(ret < stm.length) {
				if(rowpos >= rows.length) {
					auto predict = ds.readByte();
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
					size_t bpp = cast(size_t)bpp_;
					switch(predict) {
					case 1:
						for(size_t i = bpp; i < rows.length; ++i) {
							rows[i] = (rows[i] + rows[i - bpp]) & 0xff;
						}
						break;
					case 2:
						for(size_t i = 0; i < rows.length; ++i) {
							rows[i] += prev[i];
						}
						break;
					case 3:
						for(size_t i = bpp; i > 0; --i) {
							rows[i] = (rows[i] + prev[i]) / 2;
						}
						for(size_t i = bpp; i < rows.length; ++i) {
							rows[i] = (prev[i] + rows[i - bpp]) / 2;
						}
						break;
					case 4:
						for(size_t i = bpp; i > 0; i--) {
							rows[i] = (rows[i] + paeth(cast(ubyte)0, prev[i], cast(ubyte)0)) & 0xff;
						}
						for(size_t i = bpp; i < rows.length; ++i) {
							rows[i] = (rows[i] + paeth(rows[i - bpp], prev[i], prev[i - bpp])) & 0xff;
						}
						break;
					default:
						// may be zero.
						break;
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
	}
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
		int a, b;
		ubyte c;
		bool odd = false;
		ubyte[] dst;

		for(size_t i = 0; i < stm.length; ++i) {
			c = stm[i];
			if(isHex(c)) {
				if(!odd) {
					a = unhex(c);
				}
				else {
					b = unhex(c);
					dst ~= cast(ubyte)((a << 4) | b);
				}
				odd = !odd;
			}
			else if(c == '>') {
				if(odd) {
					dst ~= cast(ubyte)(a << 4);
				}
				break;
			}
			else if(!isWhite(c)) {
				throw new Error("bad data in AsciiHexDecoder: '%c'".format(c));
			}
		}
		return dst;
	}
}

class JPXDecoder : PdfDecoder
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

