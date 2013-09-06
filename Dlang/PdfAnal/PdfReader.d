module PdfStream;


class MemoryReader
{
private:
	size_t position_ = 0;
	ubyte[] buf_;

public:
	this(ubyte[] buf)
	{
		buf_ = buf;
	}

	@property size_t length()
	{
		return buf_.length;
	}

	@property size_t position()
	{
		return position_;
	}

	@property bool eof()
	{
		return (position_ >= length);
	}

	@property ubyte peek()
	{
		if(eof) return 0x00;
		return buf_[position_];
	}

	ubyte readByte()
	{
		if(eof) return 0x00;
		return buf_[position_++];
	}

	bool readNext()
	{
		if(eof) return false;
		++position_;
		return true;
	}

	bool previous()
	{
		if(position_ == 0 || length == 0) {
			return false;
		}
		--position_;
		return true;
	}

	ubyte[] readln()
	{
		auto c = position_;
		while(true) {
			if(c > length) {
				break;
			}
			if(buf_[c] == '\r') {
				if(buf_[c + 1] == '\n') {
					++c;
				}
				break;
			}
			if(buf_[c] == '\n') {
				break;
			}
			++c;
		}
		auto slice = buf_[position_..c];
		position_ = c + 1;
		return slice;
	}

	void seek(size_t pos)
	{
		if(pos >= length) {
			position_ = length - 1;
		}
		else {
			position_ = pos;
		}
	}

	ubyte[] slice(size_t b, size_t e)
	{
		return buf_[b..e];
	}
}
