using System.IO;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Imaging;

Dictionary<string, int[]> sizes = new()
{
    { "apple-touch-icon", new int[] { 1024, 180, 167, 152, 144, 120, 114, 76, 72, 60, 57 } },
    { "android-chrome", new int[] { 512, 384, 256, 192, 144, 96, 72, 48, 36 } },
    { "favicon", new int[] { 48, 32, 16 } },
};

string file = Path.GetFileName("origin.png");
if (!Directory.Exists("output"))
{
  Directory.CreateDirectory("output");
}

if (!File.Exists(file)) return;

foreach (var kv in sizes)
{
  foreach (int i in kv.Value)
  {
    int target_size = i;
    string outputfile = Path.Combine("output", $"{kv.Key}-{target_size}x{target_size}.png");
    Rectangle rect = new(0, 0, target_size, target_size);
    Bitmap img = (Bitmap)Image.FromFile(file);
    Bitmap ni = new(target_size, target_size);
    using Graphics g = Graphics.FromImage(ni);
    g.CompositingMode = CompositingMode.SourceCopy;
    g.CompositingQuality = CompositingQuality.HighQuality;
    g.SmoothingMode = SmoothingMode.HighQuality;
    g.PixelOffsetMode = PixelOffsetMode.HighQuality;
    g.InterpolationMode = InterpolationMode.HighQualityBicubic;
    using ImageAttributes wm = new();
    wm.SetWrapMode(WrapMode.TileFlipXY);
    g.DrawImage(img, rect, 0, 0, img.Width, img.Height, GraphicsUnit.Pixel, wm);
    ni.Save(outputfile, ImageFormat.Png);
  }
}
