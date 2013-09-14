module PdfGeom;

import PdfObjects;

struct Boundary
{
	float left_, bottom_, right_, top_;

	@property float left()
	{
		return left_;
	}
	@property float bottom()
	{
		return bottom_;
	}
	@property float right()
	{
		return right_;
	}
	@property float top()
	{
		return top_;
	}
	@property float x()
	{
		return left_;
	}
	@property float y()
	{
		return bottom_;
	}
	@property float width()
	{
		return (right_ - left_);
	}
	@property float height()
	{
		return (top_ - bottom_);
	}

	static Boundary fromObj(PdfArray array)
	{
		Boundary dst;
		auto vals = array.value!(PdfObject[]);
		dst.left_ = vals[0].value!float;
		dst.bottom_ = vals[1].value!float;
		dst.right_ = vals[2].value!float;
		dst.top_ = vals[3].value!float;
		return dst;
	}
}