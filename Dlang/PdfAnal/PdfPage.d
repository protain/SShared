module PdfPage;

import std.traits;
import std.string;

import PdfObjects;
import PdfGeom;
import PdfDocument;

enum BoundaryType : char
{
	MediaBox = 'm',
	CropBox = 'c',
	BleedBox = 'b',
	TrimBox = 't',
	ArtBox = 'a'
}

class PdfPage
{
private:
	PdfDictionary pageObj_;
	PdfDocument doc_;
	Boundary[BoundaryType] bounds_;
	int rotate_;

public:
	this(PdfDocument doc, PdfDictionary pobj)
	{
		pageObj_ = pobj;
		doc_ = doc;
		auto obj = pobj.dictGets("MediaBox");
		if(obj is null || obj.kind != PdfObjKind.PDF_ARRAY) {
			throw new Error("cannot recognize MediaBox");
		}
		bounds_[BoundaryType.MediaBox] = PdfGeom.Boundary.fromObj(cast(PdfArray)obj);
		obj = pobj.dictGets("CropBox");
		bounds_[BoundaryType.CropBox] = (obj is null) ?
			bounds_[BoundaryType.MediaBox] : PdfGeom.Boundary.fromObj(cast(PdfArray)obj);
		obj = pobj.dictGets("BleedBox");
		bounds_[BoundaryType.BleedBox] = (obj is null) ?
			bounds_[BoundaryType.CropBox] : PdfGeom.Boundary.fromObj(cast(PdfArray)obj);
		obj = pobj.dictGets("TrimBox");
		bounds_[BoundaryType.TrimBox] = (obj is null) ?
			bounds_[BoundaryType.CropBox] : PdfGeom.Boundary.fromObj(cast(PdfArray)obj);
		obj = pobj.dictGets("ArtBox");
		bounds_[BoundaryType.ArtBox] = (obj is null) ?
			bounds_[BoundaryType.CropBox] : PdfGeom.Boundary.fromObj(cast(PdfArray)obj);

		rotate_ = 0;
		obj = pobj.dictGets("Rotate");
		if(obj !is null && obj.kind == PdfObjKind.PDF_INT) {
			rotate_ = obj.value!int;
		}
	}

	@property PdfObject contents()
	{
		return doc_.getIndObj(pageObj_.dictGets("Contents"));
	}

	@property PdfObject resources()
	{
		return doc_.getIndObj(pageObj_.dictGets("Resources"));
	}

	@property Boundary getBoundary(BoundaryType type)
	{
		return bounds_[type];
	}

	@property int rotate()
	{
		return rotate_;
	}

	override string toString()
	{
		auto dst = "{";
		dst ~= `"Rotate":%d,`.format(rotate);
		foreach(v; EnumMembers!BoundaryType) {
			auto bb = bounds_[v];
			dst ~= `"%s":[%f, %f, %f, %f],`.format(v, bb.left, bb.bottom, bb.top, bb.right);
		}
		dst ~= `"$ContentsNo":%d,`.format((contents is null) ? -1 : contents.objno);
		dst ~= `"Contents":%s,`.format(contents);
		dst ~= `"$ResourcesNo":%d,`.format((resources is null) ? -1 : resources.objno);
		dst ~= `"Resources":%s`.format(resources);
		dst ~= "}";
		return dst;
	}
}