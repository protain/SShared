namespace CS_PdfAnalDriver
{
	partial class Form1
	{
		/// <summary>
		/// 必要なデザイナー変数です。
		/// </summary>
		private System.ComponentModel.IContainer components = null;

		/// <summary>
		/// 使用中のリソースをすべてクリーンアップします。
		/// </summary>
		/// <param name="disposing">マネージ リソースが破棄される場合 true、破棄されない場合は false です。</param>
		protected override void Dispose(bool disposing)
		{
			if(disposing && (components != null)) {
				components.Dispose();
			}
			base.Dispose(disposing);
		}

		#region Windows フォーム デザイナーで生成されたコード

		/// <summary>
		/// デザイナー サポートに必要なメソッドです。このメソッドの内容を
		/// コード エディターで変更しないでください。
		/// </summary>
		private void InitializeComponent()
		{
			this.txtStream = new System.Windows.Forms.TextBox();
			this.tvPdfDoc = new System.Windows.Forms.TreeView();
			this.menuStrip1 = new System.Windows.Forms.MenuStrip();
			this.mnuOpen = new System.Windows.Forms.ToolStripMenuItem();
			this.mnuSaveStream = new System.Windows.Forms.ToolStripMenuItem();
			this.menuStrip1.SuspendLayout();
			this.SuspendLayout();
			// 
			// txtStream
			// 
			this.txtStream.Anchor = ((System.Windows.Forms.AnchorStyles)(((System.Windows.Forms.AnchorStyles.Bottom | System.Windows.Forms.AnchorStyles.Left) 
            | System.Windows.Forms.AnchorStyles.Right)));
			this.txtStream.Location = new System.Drawing.Point(6, 280);
			this.txtStream.Margin = new System.Windows.Forms.Padding(2);
			this.txtStream.Multiline = true;
			this.txtStream.Name = "txtStream";
			this.txtStream.ScrollBars = System.Windows.Forms.ScrollBars.Both;
			this.txtStream.Size = new System.Drawing.Size(443, 141);
			this.txtStream.TabIndex = 0;
			// 
			// tvPdfDoc
			// 
			this.tvPdfDoc.Anchor = ((System.Windows.Forms.AnchorStyles)((((System.Windows.Forms.AnchorStyles.Top | System.Windows.Forms.AnchorStyles.Bottom) 
            | System.Windows.Forms.AnchorStyles.Left) 
            | System.Windows.Forms.AnchorStyles.Right)));
			this.tvPdfDoc.Location = new System.Drawing.Point(6, 29);
			this.tvPdfDoc.Margin = new System.Windows.Forms.Padding(2);
			this.tvPdfDoc.Name = "tvPdfDoc";
			this.tvPdfDoc.Size = new System.Drawing.Size(443, 240);
			this.tvPdfDoc.TabIndex = 1;
			this.tvPdfDoc.NodeMouseClick += new System.Windows.Forms.TreeNodeMouseClickEventHandler(this.tvPdfDoc_NodeMouseClick);
			this.tvPdfDoc.NodeMouseDoubleClick += new System.Windows.Forms.TreeNodeMouseClickEventHandler(this.tvPdfDoc_NodeMouseDoubleClick);
			// 
			// menuStrip1
			// 
			this.menuStrip1.Items.AddRange(new System.Windows.Forms.ToolStripItem[] {
            this.mnuOpen,
            this.mnuSaveStream});
			this.menuStrip1.Location = new System.Drawing.Point(0, 0);
			this.menuStrip1.Name = "menuStrip1";
			this.menuStrip1.Padding = new System.Windows.Forms.Padding(3, 1, 0, 1);
			this.menuStrip1.Size = new System.Drawing.Size(453, 24);
			this.menuStrip1.TabIndex = 2;
			this.menuStrip1.Text = "menuStrip1";
			// 
			// mnuOpen
			// 
			this.mnuOpen.Name = "mnuOpen";
			this.mnuOpen.Size = new System.Drawing.Size(44, 22);
			this.mnuOpen.Text = "開く";
			this.mnuOpen.Click += new System.EventHandler(this.mnuOpen_Click);
			// 
			// mnuSaveStream
			// 
			this.mnuSaveStream.Name = "mnuSaveStream";
			this.mnuSaveStream.Size = new System.Drawing.Size(116, 22);
			this.mnuSaveStream.Text = "ストリームを保存";
			this.mnuSaveStream.Click += new System.EventHandler(this.mnuSaveStream_Click);
			// 
			// Form1
			// 
			this.AutoScaleDimensions = new System.Drawing.SizeF(6F, 12F);
			this.AutoScaleMode = System.Windows.Forms.AutoScaleMode.Font;
			this.ClientSize = new System.Drawing.Size(453, 465);
			this.Controls.Add(this.tvPdfDoc);
			this.Controls.Add(this.txtStream);
			this.Controls.Add(this.menuStrip1);
			this.MainMenuStrip = this.menuStrip1;
			this.Margin = new System.Windows.Forms.Padding(2);
			this.Name = "Form1";
			this.Text = "Form1";
			this.menuStrip1.ResumeLayout(false);
			this.menuStrip1.PerformLayout();
			this.ResumeLayout(false);
			this.PerformLayout();

		}

		#endregion

		private System.Windows.Forms.TextBox txtStream;
		private System.Windows.Forms.TreeView tvPdfDoc;
		private System.Windows.Forms.MenuStrip menuStrip1;
		private System.Windows.Forms.ToolStripMenuItem mnuOpen;
		private System.Windows.Forms.ToolStripMenuItem mnuSaveStream;
	}
}

