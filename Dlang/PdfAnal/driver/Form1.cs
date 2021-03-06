﻿using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Data;
using System.Diagnostics;
using System.Drawing;
using System.IO;
using System.Linq;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading.Tasks;
using System.Windows.Forms;
using Newtonsoft.Json;

namespace CS_PdfAnalDriver
{
	public partial class Form1 : Form
	{
		class PdfAnal
		{
			[DllImport("Dlang_PdfAnal.dll", CallingConvention=CallingConvention.Cdecl)]
			public extern static ulong getPdfDocument(string pdfpath);
			[DllImport("Dlang_PdfAnal.dll", CallingConvention=CallingConvention.Cdecl)]
			public extern static void saveDocument(ulong key, string pdfpath);
			[DllImport("Dlang_PdfAnal.dll", CallingConvention=CallingConvention.Cdecl)]
			public extern static ulong analDocument(ulong key);
			[DllImport("Dlang_PdfAnal.dll", CallingConvention=CallingConvention.Cdecl)]
			public extern static ulong analPages(ulong key);
			[DllImport("Dlang_PdfAnal.dll", CallingConvention=CallingConvention.Cdecl)]
			public extern static void getBuff(ulong key, StringBuilder buf);
			[DllImport("Dlang_PdfAnal.dll", CallingConvention=CallingConvention.Cdecl)]
			public extern static void getBuff(ulong key, byte[] buf);
			[DllImport("Dlang_PdfAnal.dll", CallingConvention=CallingConvention.Cdecl)]
			public extern static void closeDocument(ulong key);
			[DllImport("Dlang_PdfAnal.dll", CallingConvention=CallingConvention.Cdecl)]
			public extern static ulong analObjStream(ulong key, int objno);
			[DllImport("Dlang_PdfAnal.dll", CallingConvention=CallingConvention.Cdecl)]
			public extern static ulong analObject(ulong key, int objno);
			[DllImport("Dlang_PdfAnal.dll", CallingConvention = CallingConvention.Cdecl)]
			public extern static bool updateObjectValue(ulong key, int objno, string keyz, string value);
			[DllImport("Dlang_PdfAnal.dll", CallingConvention = CallingConvention.Cdecl)]
			public extern static bool updateObjectStream(ulong key, int objno, byte[] buff, ulong buflen);
		}

		public Form1()
		{
			InitializeComponent();
			key_ = 0;

			Func<Object, bool> isJsObj = (o) => { return o is JavaScriptArray || o is JavaScriptObject; };
			jsoFunc = (o, klbl, tv, tn, isObj, lvl) =>
			{
				++lvl;
				try {
					if(o is JavaScriptArray) {
						var jary = o as JavaScriptArray;
						for(int i = 0; i < jary.Count; ++i) {
							var lbl = "[" + i.ToString() + "]";
							var tcn = new TreeNode(lbl);
							if(isObj) {
								tcn.ForeColor = Color.Red;
							}
							tcn.Tag = new ObjInfo { idx_ = isObj ? i : -1, pdfObj_ = jary[i] as JavaScriptObject };
							if(!isJsObj(jary[i])) {
								lbl = lbl + " : " + (jary[i] == null ? "null" : jary[i].ToString());
								tcn.Text = lbl;
								if(tv == null) tn.Nodes.Add(tcn); else tv.Nodes.Add(tcn);
							}
							else {
								if(tv == null) tn.Nodes.Add(tcn); else tv.Nodes.Add(tcn);
								jsoFunc(jary[i], "", null, tcn, (lvl == 1 && i == 1), lvl);
							}
						}
					}
					else if(o is JavaScriptObject) {
						var jobj = o as JavaScriptObject;
						foreach(var key in jobj.Keys) {
							if(isJsObj(jobj[key])) {
								var tcn = new TreeNode(key);
								var objinf = new ObjInfo { idx_ = -1, pdfObj_ = jobj[key] as JavaScriptObject };
								if(jobj.ContainsKey("$ContentsNo")) {
									objinf.idx_ = Convert.ToInt32(jobj["$ContentsNo"]);
								}
								else if(jobj.ContainsKey("$ResourcesNo")) {
									objinf.idx_ = Convert.ToInt32(jobj["$ResourcesNo"]);
								}
								tcn.Tag = objinf;
								if(tv == null) tn.Nodes.Add(tcn); else tv.Nodes.Add(tcn);
								jsoFunc(jobj[key], key, null, tcn, false, lvl);
							}
							else {
								var tcn = new TreeNode(key + " : " + (jobj[key] == null ? "null" : jobj[key].ToString()));
								if(tv == null) tn.Nodes.Add(tcn); else tv.Nodes.Add(tcn);
							}
						}
					}
					else {
						var vstr = o == null ? "null" : o.ToString();
						var lbl = "";
						if(string.IsNullOrEmpty(klbl)) lbl = klbl + " : " + vstr; else lbl = vstr;
						var tcn = new TreeNode(lbl);
						if(tv == null) tn.Nodes.Add(tcn); else tv.Nodes.Add(tcn);
					}
				}
				finally {
					--lvl;
				}
			};
	}

		private ulong key_ = 0;
		private string fname_ = string.Empty;

		class ObjInfo
		{
			public int idx_ = 1;
			public JavaScriptObject pdfObj_;
			public bool refresolve_ = false;
		}

		Action<Object, string, TreeView, TreeNode, bool, int> jsoFunc;

		private void mnuOpen_Click(object sender, EventArgs e)
		{
			var ofn = new OpenFileDialog();
			ofn.Filter = "PDF Document(*.pdf)|*.pdf";
			if(ofn.ShowDialog() != System.Windows.Forms.DialogResult.OK) {
				return;
			}
			if(key_ != 0) {
				PdfAnal.closeDocument(key_);
				GC.Collect();
				key_ = 0;
				tvPdfDoc.Nodes.Clear();
			}

			fname_ = ofn.FileName;
			this.Text = fname_;
			key_ = PdfAnal.getPdfDocument(ofn.FileName);
			//MessageBox.Show(key_.ToString());
			Debug.Write(key_.ToString());
			if(key_ == 0) {
				return;
			}
			//var len = PdfAnal.analDocument(key_);
			var len = PdfAnal.analPages(key_);
			//MessageBox.Show(len.ToString());
			var buff = new byte[len]; //new StringBuilder((int)len);
			PdfAnal.getBuff(key_, buff);

			var docstr = Encoding.UTF8.GetString(buff);

			var jsr = new Newtonsoft.Json.JsonReader(new StringReader(docstr));
			var js = new Newtonsoft.Json.JsonSerializer();
			var jsroot = js.Deserialize(jsr);

			//Action<Object, string, TreeView, TreeNode, bool> jsoFunc = null;
			int lvl = 0;
			tvPdfDoc.Update();
			jsoFunc(jsroot, "", tvPdfDoc, null, false, lvl);
			tvPdfDoc.EndUpdate();
		}

		private void mnuRawOpenToolStripMenuItem_Click(object sender, EventArgs e)
		{
			var ofn = new OpenFileDialog();
			ofn.Filter = "PDF Document(*.pdf)|*.pdf";
			if(ofn.ShowDialog() != System.Windows.Forms.DialogResult.OK) {
				return;
			}
			if(key_ != 0) {
				PdfAnal.closeDocument(key_);
				GC.Collect();
				key_ = 0;
				tvPdfDoc.Nodes.Clear();
			}

			fname_ = ofn.FileName;
			this.Text = fname_;
			key_ = PdfAnal.getPdfDocument(ofn.FileName);
			Debug.Write(key_.ToString());
			if(key_ == 0) {
				return;
			}
			var len = PdfAnal.analDocument(key_);
			var buff = new byte[len];
			PdfAnal.getBuff(key_, buff);

			var docstr = Encoding.UTF8.GetString(buff);

			var jsr = new Newtonsoft.Json.JsonReader(new StringReader(docstr));
			var js = new Newtonsoft.Json.JsonSerializer();
			var jsroot = js.Deserialize(jsr);

			int lvl = 0;
			tvPdfDoc.Update();
			jsoFunc(jsroot, "", tvPdfDoc, null, false, lvl);
			tvPdfDoc.EndUpdate();
		}

		private void tvPdfDoc_NodeMouseDoubleClick(object sender, TreeNodeMouseClickEventArgs e)
		{
		}

		private void tvPdfDoc_NodeMouseClick(object sender, TreeNodeMouseClickEventArgs e)
		{
			if(e.Node.Tag == null || key_ == 0) {
				return;
			}

			txtStream.Text = string.Empty;
			var idxObj = e.Node.Tag as ObjInfo;
			var idx = -1;
			if(idxObj != null && idxObj.idx_ >= 0) {
				idx = idxObj.idx_;
			}
			else if(chkRefResolve.Checked && idxObj.pdfObj_ != null && idxObj.pdfObj_.ContainsKey("$Type") && idxObj.refresolve_ == false) {
				// resolve obj ref;
				var objnum = Convert.ToInt32(idxObj.pdfObj_["num"]);
				idxObj.idx_ = objnum;
				var len = PdfAnal.analObject(key_, objnum);
				var buff = new byte[len]; //new StringBuilder((int)len);
				PdfAnal.getBuff(key_, buff);

				var docstr = Encoding.UTF8.GetString(buff);

				var jsr = new Newtonsoft.Json.JsonReader(new StringReader(docstr));
				var js = new Newtonsoft.Json.JsonSerializer();
				var jsroot = js.Deserialize(jsr);

				e.Node.Nodes.Clear();
				jsoFunc(jsroot, "", null, e.Node, false, 10);	// 10は適当

				e.Node.Text = string.Format("{0} ({1} 0 R)", e.Node.Text, objnum);
			}
			else {
				return;
			}
			var stmlen = PdfAnal.analObjStream(key_, idx);
			if(stmlen == 0) {
				return;
			}
			var stmbuf = new byte[stmlen];
			PdfAnal.getBuff(key_, stmbuf);
			var tmpPath = Path.Combine(Path.GetTempPath(), "pdfanl.tmp");
			using(var tmp = new FileStream(tmpPath, FileMode.Create, FileAccess.Write)) {
				tmp.Write(stmbuf, 0, stmbuf.Length);
			}
			using(var tmp = new StreamReader(tmpPath)) {
				var txtBuf = new StringBuilder();
				while(true) {
					var line = tmp.ReadLine();
					if(line == null || txtBuf.Length > (2 << 15)) {
						break;
					}
					txtBuf.AppendLine(line);
				}
				txtStream.Text = txtBuf.ToString();
			}
		}

		private void mnuSaveStream_Click(object sender, EventArgs e)
		{
			var trg = tvPdfDoc.SelectedNode;
			if(trg == null || trg.Tag == null || key_ == 0) {
				return;
			}
			var idx = (trg.Tag as ObjInfo).idx_;
			var stmlen = PdfAnal.analObjStream(key_, idx);
			if(stmlen == 0) {
				return;
			}
			var stmbuf = new byte[stmlen];
			PdfAnal.getBuff(key_, stmbuf);
			var sfd = new SaveFileDialog();
			sfd.FileName = Path.GetFileNameWithoutExtension(fname_) + "_obj" + idx.ToString() + ".txt";
			if(sfd.ShowDialog() != System.Windows.Forms.DialogResult.OK) {
				return;
			}
			using(var fs = new FileStream(sfd.FileName, FileMode.Create, FileAccess.Write)) {
				fs.Write(stmbuf, 0, stmbuf.Length);
			}
		}

		private void mnuSaveDocToolStripMenuItem_Click(object sender, EventArgs e)
		{
			var sfd = new SaveFileDialog();
			if(sfd.ShowDialog() != System.Windows.Forms.DialogResult.OK) {
				return;
			}
			PdfAnal.saveDocument(key_, sfd.FileName);
		}
	}
}
