using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Diagnostics;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.IO;
using System.Net;
using System.Runtime.InteropServices;
using System.Text;
using System.Text.RegularExpressions;
using System.Threading;
using System.Threading.Tasks;
using System.Windows.Forms;
using System.Web.Script.Serialization;
using Microsoft.Web.WebView2.Core;
using Microsoft.Web.WebView2.WinForms;

namespace SunoDownloaderApp
{
    static class Program
    {
        [DllImport("user32.dll")]
        public static extern bool SetForegroundWindow(IntPtr hWnd);

        [DllImport("user32.dll")]
        public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);

        [DllImport("dwmapi.dll")]
        private static extern int DwmSetWindowAttribute(IntPtr hwnd, int attr, ref int attrValue, int attrSize);

        private static Mutex appMutex;

        [STAThread]
        static void Main(string[] args)
        {
            Application.EnableVisualStyles();
            Application.SetCompatibleTextRenderingDefault(false);

            string initialUrl = "";
            bool autoDownload = false;
            string format = "wav";

            for (int i = 0; i < args.Length; i++)
            {
                if ((args[i] == "--url" || args[i] == "-u") && i + 1 < args.Length)
                {
                    initialUrl = args[i + 1];
                    i++;
                }
                else if (args[i] == "--auto")
                {
                    autoDownload = true;
                }
                else if ((args[i] == "--format" || args[i] == "-f") && i + 1 < args.Length)
                {
                    format = args[i + 1].ToLower();
                    i++;
                }
                else if (args[i].StartsWith("http://") || args[i].StartsWith("https://"))
                {
                    initialUrl = args[i];
                }
            }

            bool isNewInstance = false;
            try
            {
                appMutex = new Mutex(true, "Local\\SunoDownloader_SingleInstance_Mutex_78912", out isNewInstance);
            }
            catch
            {
                isNewInstance = true;
            }

            if (!isNewInstance && !string.IsNullOrEmpty(initialUrl))
            {
                try
                {
                    string queueFile = Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "download_queue.json");
                    List<Dictionary<string, object>> queue = new List<Dictionary<string, object>>();
                    JavaScriptSerializer js = new JavaScriptSerializer();
                    if (File.Exists(queueFile))
                    {
                        string existing = File.ReadAllText(queueFile);
                        if (!string.IsNullOrEmpty(existing))
                        {
                            try
                            {
                                var parsed = js.Deserialize<List<Dictionary<string, object>>>(existing);
                                if (parsed != null) queue = parsed;
                            }
                            catch { }
                        }
                    }
                    var item = new Dictionary<string, object>();
                    item["url"] = initialUrl;
                    item["format"] = format;
                    item["timestamp"] = DateTime.UtcNow.Ticks;
                    queue.Add(item);
                    File.WriteAllText(queueFile, js.Serialize(queue));
                }
                catch { }
                return;
            }

            Application.Run(new DownloaderForm(initialUrl, autoDownload, format));
        }

        public class DownloaderForm : Form
        {
            // UI Controls
            private TextBox txtUrl;
            private Button btnPaste;
            private Button btnInspect;
            private RadioButton rbWav;
            private RadioButton rbMp3;
            private TextBox txtSavePath;
            private Button btnBrowse;
            private CheckBox chkAutoWatch;
            private Button btnDownload;
            private ProgressBar progressBar;
            private Label lblStatus;
            private PictureBox picCover;
            private Label lblSongTitle;
            private Label lblSongMeta;
            private ListView lvHistory;
            private Button btnPlay;
            private Button btnOpenFolder;
            private Button btnClearHistory;
            private Panel pnlCardInput;
            private Panel pnlCardStatus;
            private Panel pnlCardHistory;
            private WebView2 hiddenWebView;

            private FileSystemWatcher queueWatcher;
            private JavaScriptSerializer jsonSerializer = new JavaScriptSerializer();
            private HashSet<string> processedUrls = new HashSet<string>();
            private string ffmpegPath = "ffmpeg.exe";
            private bool isDownloading = false;

            public DownloaderForm(string initUrl, bool autoRun, string defaultFormat)
            {
                this.Text = "Suno Downloader - កម្មវិធីទាញយកបទចម្រៀង Suno (WAV / MP3)";
                this.Width = 920;
                this.Height = 720;
                this.MinimumSize = new Size(820, 640);
                this.StartPosition = FormStartPosition.CenterScreen;
                this.BackColor = Color.FromArgb(16, 16, 20);
                this.ForeColor = Color.White;
                this.Font = new Font("Segoe UI", 9.5f);

                try
                {
                    int darkMode = 1;
                    DwmSetWindowAttribute(this.Handle, 20, ref darkMode, sizeof(int));
                    DwmSetWindowAttribute(this.Handle, 19, ref darkMode, sizeof(int));
                }
                catch { }

                try
                {
                    string iconPath = Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "app.ico");
                    if (File.Exists(iconPath)) this.Icon = new Icon(iconPath);
                }
                catch { }

                LocateFFmpeg();
                BuildUI();
                InitializeWatcher();

                if (!string.IsNullOrEmpty(initUrl))
                {
                    txtUrl.Text = initUrl;
                    if (autoRun)
                    {
                        this.Shown += (s, e) => StartDownload(initUrl, rbWav.Checked ? "wav" : "mp3");
                    }
                    else
                    {
                        this.Shown += (s, e) => InspectSong(initUrl);
                    }
                }

                this.Load += async (s, e) => await InitializeHiddenWebView();
            }

            private void LocateFFmpeg()
            {
                try
                {
                    var p = Process.Start(new ProcessStartInfo("ffmpeg.exe", "-version")
                    {
                        CreateNoWindow = true,
                        UseShellExecute = false,
                        RedirectStandardOutput = true
                    });
                    p.WaitForExit(1000);
                    if (p.ExitCode == 0)
                    {
                        ffmpegPath = "ffmpeg.exe";
                        return;
                    }
                }
                catch { }

                string wingetPath = @"C:\Users\PS\AppData\Local\Microsoft\WinGet\Packages\Gyan.FFmpeg_Microsoft.Winget.Source_8wekyb3d8bbwe\ffmpeg-9.0.2-full_build\bin\ffmpeg.exe";
                if (File.Exists(wingetPath))
                {
                    ffmpegPath = wingetPath;
                    return;
                }

                string localFfmpeg = Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "ffmpeg.exe");
                if (File.Exists(localFfmpeg))
                {
                    ffmpegPath = localFfmpeg;
                }
            }

            private async Task InitializeHiddenWebView()
            {
                try
                {
                    hiddenWebView = new WebView2
                    {
                        Visible = false,
                        Dock = DockStyle.None,
                        Size = new Size(10, 10)
                    };
                    this.Controls.Add(hiddenWebView);

                    string appData = Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData);
                    string userDataFolder = Path.Combine(appData, "SunoDesktop", "UserData");

                    CoreWebView2Environment env = null;
                    bool useFallback = false;
                    try
                    {
                        env = await CoreWebView2Environment.CreateAsync(null, userDataFolder);
                        await hiddenWebView.EnsureCoreWebView2Async(env);
                    }
                    catch
                    {
                        useFallback = true;
                    }

                    if (useFallback)
                    {
                        string fallback = Path.Combine(appData, "SunoDesktop", "UserData_Alt");
                        env = await CoreWebView2Environment.CreateAsync(null, fallback);
                        await hiddenWebView.EnsureCoreWebView2Async(env);
                    }

                    hiddenWebView.Source = new Uri("https://suno.com/create");
                }
                catch (Exception ex)
                {
                    Debug.WriteLine("Hidden WebView2 notice: " + ex.Message);
                }
            }

            private void BuildUI()
            {
                Panel pnlHeader = new Panel
                {
                    Dock = DockStyle.Top,
                    Height = 70,
                    BackColor = Color.FromArgb(22, 22, 28),
                    Padding = new Padding(20, 10, 20, 10)
                };

                Label lblHeaderTitle = new Label
                {
                    Text = "🎵 Suno Song Downloader (កម្មវិធីទាញយកបទចម្រៀង Suno)",
                    Font = new Font("Segoe UI", 13.5f, FontStyle.Bold),
                    ForeColor = Color.FromArgb(255, 110, 80),
                    AutoSize = true,
                    Location = new Point(18, 12)
                };

                Label lblHeaderSub = new Label
                {
                    Text = "ទាញយកបទចម្រៀងតាមរយៈ Link URL ដោយផ្ទាល់ និង បំលែងជា Lossless 16-bit 44.1kHz WAV ឬ 320kbps MP3",
                    Font = new Font("Segoe UI", 9.0f),
                    ForeColor = Color.FromArgb(160, 160, 175),
                    AutoSize = true,
                    Location = new Point(20, 40)
                };

                pnlHeader.Controls.Add(lblHeaderTitle);
                pnlHeader.Controls.Add(lblHeaderSub);
                this.Controls.Add(pnlHeader);

                Panel pnlBody = new Panel
                {
                    Dock = DockStyle.Fill,
                    AutoScroll = true,
                    Padding = new Padding(20, 15, 20, 15)
                };
                this.Controls.Add(pnlBody);

                // 1. INPUT CARD
                pnlCardInput = CreateCardPanel(190);
                pnlCardInput.Location = new Point(20, 15);
                pnlCardInput.Width = this.ClientSize.Width - 60;
                pnlCardInput.Anchor = AnchorStyles.Top | AnchorStyles.Left | AnchorStyles.Right;

                Label lblUrlPrompt = new Label
                {
                    Text = "🔗 បញ្ចូល Link URL បទចម្រៀង Suno (Song Link URL):",
                    Font = new Font("Segoe UI", 9.5f, FontStyle.Bold),
                    ForeColor = Color.FromArgb(230, 230, 240),
                    Location = new Point(16, 14),
                    AutoSize = true
                };

                txtUrl = new TextBox
                {
                    Location = new Point(18, 38),
                    Width = pnlCardInput.Width - 230,
                    Anchor = AnchorStyles.Top | AnchorStyles.Left | AnchorStyles.Right,
                    Font = new Font("Segoe UI", 10.5f),
                    BackColor = Color.FromArgb(28, 28, 36),
                    ForeColor = Color.White,
                    BorderStyle = BorderStyle.FixedSingle
                };

                btnPaste = new Button
                {
                    Text = "📋 បិទភ្ជាប់ (Paste)",
                    Location = new Point(pnlCardInput.Width - 200, 36),
                    Size = new Size(100, 30),
                    Anchor = AnchorStyles.Top | AnchorStyles.Right,
                    BackColor = Color.FromArgb(40, 40, 52),
                    ForeColor = Color.White,
                    FlatStyle = FlatStyle.Flat
                };
                btnPaste.FlatAppearance.BorderColor = Color.FromArgb(70, 70, 90);
                btnPaste.Click += (s, e) =>
                {
                    if (Clipboard.ContainsText())
                    {
                        txtUrl.Text = Clipboard.GetText().Trim();
                        InspectSong(txtUrl.Text);
                    }
                };

                btnInspect = new Button
                {
                    Text = "🔍 ពិនិត្យបទ",
                    Location = new Point(pnlCardInput.Width - 92, 36),
                    Size = new Size(80, 30),
                    Anchor = AnchorStyles.Top | AnchorStyles.Right,
                    BackColor = Color.FromArgb(40, 40, 52),
                    ForeColor = Color.White,
                    FlatStyle = FlatStyle.Flat
                };
                btnInspect.FlatAppearance.BorderColor = Color.FromArgb(70, 70, 90);
                btnInspect.Click += (s, e) => InspectSong(txtUrl.Text);

                Label lblFormat = new Label
                {
                    Text = "🎵 ទម្រង់សម្លេង (Format):",
                    Font = new Font("Segoe UI", 9.0f, FontStyle.Bold),
                    ForeColor = Color.FromArgb(200, 200, 215),
                    Location = new Point(16, 80),
                    AutoSize = true
                };

                rbWav = new RadioButton
                {
                    Text = "WAV (Lossless 16-bit 44.1kHz Stereo PCM) ⭐ [ណែនាំ]",
                    Location = new Point(190, 78),
                    AutoSize = true,
                    Checked = true,
                    ForeColor = Color.FromArgb(100, 220, 255),
                    Font = new Font("Segoe UI", 9.0f, FontStyle.Bold)
                };

                rbMp3 = new RadioButton
                {
                    Text = "MP3 (320 kbps High Quality Audio)",
                    Location = new Point(530, 78),
                    AutoSize = true,
                    ForeColor = Color.FromArgb(210, 210, 220),
                    Font = new Font("Segoe UI", 9.0f)
                };

                Label lblSaveTo = new Label
                {
                    Text = "📁 រក្សាទុកក្នុង (Save To):",
                    Font = new Font("Segoe UI", 9.0f, FontStyle.Bold),
                    ForeColor = Color.FromArgb(200, 200, 215),
                    Location = new Point(16, 114),
                    AutoSize = true
                };

                string defaultDl = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), "Downloads");
                txtSavePath = new TextBox
                {
                    Location = new Point(190, 110),
                    Width = pnlCardInput.Width - 305,
                    Anchor = AnchorStyles.Top | AnchorStyles.Left | AnchorStyles.Right,
                    Font = new Font("Segoe UI", 9.5f),
                    BackColor = Color.FromArgb(28, 28, 36),
                    ForeColor = Color.White,
                    Text = defaultDl,
                    BorderStyle = BorderStyle.FixedSingle
                };

                btnBrowse = new Button
                {
                    Text = "📂 ជ្រើសរើស...",
                    Location = new Point(pnlCardInput.Width - 105, 108),
                    Size = new Size(92, 28),
                    Anchor = AnchorStyles.Top | AnchorStyles.Right,
                    BackColor = Color.FromArgb(40, 40, 52),
                    ForeColor = Color.White,
                    FlatStyle = FlatStyle.Flat
                };
                btnBrowse.FlatAppearance.BorderColor = Color.FromArgb(70, 70, 90);
                btnBrowse.Click += (s, e) =>
                {
                    using (FolderBrowserDialog fbd = new FolderBrowserDialog())
                    {
                        fbd.SelectedPath = txtSavePath.Text;
                        if (fbd.ShowDialog() == DialogResult.OK)
                        {
                            txtSavePath.Text = fbd.SelectedPath;
                        }
                    }
                };

                chkAutoWatch = new CheckBox
                {
                    Text = "⚡ ស្វ័យប្រវត្តិចាប់យកបទចម្រៀងថ្មីពី Suno នៅពេលបង្កើតរួច (Auto-Download Watcher Active)",
                    Location = new Point(18, 150),
                    AutoSize = true,
                    Checked = true,
                    ForeColor = Color.FromArgb(80, 230, 160),
                    Font = new Font("Segoe UI", 9.5f, FontStyle.Bold)
                };

                pnlCardInput.Controls.Add(lblUrlPrompt);
                pnlCardInput.Controls.Add(txtUrl);
                pnlCardInput.Controls.Add(btnPaste);
                pnlCardInput.Controls.Add(btnInspect);
                pnlCardInput.Controls.Add(lblFormat);
                pnlCardInput.Controls.Add(rbWav);
                pnlCardInput.Controls.Add(rbMp3);
                pnlCardInput.Controls.Add(lblSaveTo);
                pnlCardInput.Controls.Add(txtSavePath);
                pnlCardInput.Controls.Add(btnBrowse);
                pnlCardInput.Controls.Add(chkAutoWatch);

                pnlBody.Controls.Add(pnlCardInput);

                // 2. STATUS & ACTION CARD
                pnlCardStatus = CreateCardPanel(150);
                pnlCardStatus.Location = new Point(20, 220);
                pnlCardStatus.Width = this.ClientSize.Width - 60;
                pnlCardStatus.Anchor = AnchorStyles.Top | AnchorStyles.Left | AnchorStyles.Right;

                picCover = new PictureBox
                {
                    Location = new Point(16, 16),
                    Size = new Size(118, 118),
                    BackColor = Color.FromArgb(30, 30, 40),
                    SizeMode = PictureBoxSizeMode.Zoom,
                    BorderStyle = BorderStyle.FixedSingle
                };

                lblSongTitle = new Label
                {
                    Text = "រង់ចាំ Link URL ឬ បទចម្រៀងថ្មីពី Suno...",
                    Font = new Font("Segoe UI", 11.5f, FontStyle.Bold),
                    ForeColor = Color.White,
                    Location = new Point(148, 16),
                    Size = new Size(pnlCardStatus.Width - 360, 28),
                    Anchor = AnchorStyles.Top | AnchorStyles.Left | AnchorStyles.Right
                };

                lblSongMeta = new Label
                {
                    Text = "បញ្ចូល Link ខាងលើ រួចចុចប៊ូតុងទាញយក ឬ បង្កើតចម្រៀងក្នុង Suno ដើម្បីទាញយកស្វ័យប្រវត្តិ។",
                    Font = new Font("Segoe UI", 9.0f),
                    ForeColor = Color.FromArgb(160, 160, 175),
                    Location = new Point(150, 48),
                    Size = new Size(pnlCardStatus.Width - 360, 24),
                    Anchor = AnchorStyles.Top | AnchorStyles.Left | AnchorStyles.Right
                };

                progressBar = new ProgressBar
                {
                    Location = new Point(150, 78),
                    Size = new Size(pnlCardStatus.Width - 360, 20),
                    Anchor = AnchorStyles.Top | AnchorStyles.Left | AnchorStyles.Right,
                    Style = ProgressBarStyle.Blocks,
                    Value = 0
                };

                lblStatus = new Label
                {
                    Text = "🟢 រួចរាល់សម្រាប់ការទាញយក (Ready)",
                    Font = new Font("Segoe UI", 9.0f, FontStyle.Italic),
                    ForeColor = Color.FromArgb(120, 220, 140),
                    Location = new Point(150, 104),
                    AutoSize = true
                };

                btnDownload = new Button
                {
                    Text = "⬇️ ទាញយកចម្រៀង\n(Download Now)",
                    Location = new Point(pnlCardStatus.Width - 190, 18),
                    Size = new Size(174, 114),
                    Anchor = AnchorStyles.Top | AnchorStyles.Right,
                    BackColor = Color.FromArgb(255, 90, 60),
                    ForeColor = Color.White,
                    Font = new Font("Segoe UI", 11.0f, FontStyle.Bold),
                    FlatStyle = FlatStyle.Flat,
                    Cursor = Cursors.Hand
                };
                btnDownload.FlatAppearance.BorderSize = 0;
                btnDownload.Click += (s, e) => StartDownload(txtUrl.Text, rbWav.Checked ? "wav" : "mp3");

                pnlCardStatus.Controls.Add(picCover);
                pnlCardStatus.Controls.Add(lblSongTitle);
                pnlCardStatus.Controls.Add(lblSongMeta);
                pnlCardStatus.Controls.Add(progressBar);
                pnlCardStatus.Controls.Add(lblStatus);
                pnlCardStatus.Controls.Add(btnDownload);

                pnlBody.Controls.Add(pnlCardStatus);

                // 3. HISTORY CARD
                pnlCardHistory = CreateCardPanel(240);
                pnlCardHistory.Location = new Point(20, 385);
                pnlCardHistory.Width = this.ClientSize.Width - 60;
                pnlCardHistory.Height = this.ClientSize.Height - 480;
                pnlCardHistory.Anchor = AnchorStyles.Top | AnchorStyles.Bottom | AnchorStyles.Left | AnchorStyles.Right;

                Label lblHistTitle = new Label
                {
                    Text = "📜 បញ្ជីបទចម្រៀងដែលបានទាញយក (Download History):",
                    Font = new Font("Segoe UI", 9.5f, FontStyle.Bold),
                    ForeColor = Color.FromArgb(220, 220, 235),
                    Location = new Point(16, 12),
                    AutoSize = true
                };

                lvHistory = new ListView
                {
                    Location = new Point(16, 38),
                    Size = new Size(pnlCardHistory.Width - 32, pnlCardHistory.Height - 88),
                    Anchor = AnchorStyles.Top | AnchorStyles.Bottom | AnchorStyles.Left | AnchorStyles.Right,
                    View = View.Details,
                    FullRowSelect = true,
                    GridLines = true,
                    BackColor = Color.FromArgb(24, 24, 30),
                    ForeColor = Color.White,
                    Font = new Font("Segoe UI", 9.0f),
                    BorderStyle = BorderStyle.FixedSingle
                };

                lvHistory.Columns.Add("ចំណងជើងបទចម្រៀង (Title)", 300);
                lvHistory.Columns.Add("ទម្រង់ (Format)", 90);
                lvHistory.Columns.Add("ទំហំ (Size)", 100);
                lvHistory.Columns.Add("កាលបរិច្ឆេទ (Date)", 140);
                lvHistory.Columns.Add("ទីតាំងឯកសារ (Path)", 220);

                btnPlay = new Button
                {
                    Text = "▶️ ចាក់ស្តាប់ (Play)",
                    Location = new Point(16, pnlCardHistory.Height - 42),
                    Size = new Size(130, 30),
                    Anchor = AnchorStyles.Bottom | AnchorStyles.Left,
                    BackColor = Color.FromArgb(36, 140, 100),
                    ForeColor = Color.White,
                    FlatStyle = FlatStyle.Flat,
                    Font = new Font("Segoe UI", 9.0f, FontStyle.Bold)
                };
                btnPlay.FlatAppearance.BorderSize = 0;
                btnPlay.Click += (s, e) => PlaySelectedFile();

                btnOpenFolder = new Button
                {
                    Text = "📂 បើកថតផ្ទុក (Open Folder)",
                    Location = new Point(155, pnlCardHistory.Height - 42),
                    Size = new Size(160, 30),
                    Anchor = AnchorStyles.Bottom | AnchorStyles.Left,
                    BackColor = Color.FromArgb(50, 50, 65),
                    ForeColor = Color.White,
                    FlatStyle = FlatStyle.Flat
                };
                btnOpenFolder.FlatAppearance.BorderSize = 0;
                btnOpenFolder.Click += (s, e) => OpenSelectedFolder();

                btnClearHistory = new Button
                {
                    Text = "🗑️ សម្អាតបញ្ជី (Clear)",
                    Location = new Point(pnlCardHistory.Width - 130, pnlCardHistory.Height - 42),
                    Size = new Size(114, 30),
                    Anchor = AnchorStyles.Bottom | AnchorStyles.Right,
                    BackColor = Color.FromArgb(50, 50, 65),
                    ForeColor = Color.FromArgb(220, 180, 180),
                    FlatStyle = FlatStyle.Flat
                };
                btnClearHistory.FlatAppearance.BorderSize = 0;
                btnClearHistory.Click += (s, e) => lvHistory.Items.Clear();

                pnlCardHistory.Controls.Add(lblHistTitle);
                pnlCardHistory.Controls.Add(lvHistory);
                pnlCardHistory.Controls.Add(btnPlay);
                pnlCardHistory.Controls.Add(btnOpenFolder);
                pnlCardHistory.Controls.Add(btnClearHistory);

                pnlBody.Controls.Add(pnlCardHistory);
            }

            private Panel CreateCardPanel(int height)
            {
                return new Panel
                {
                    Height = height,
                    BackColor = Color.FromArgb(24, 24, 30),
                    BorderStyle = BorderStyle.None,
                    Padding = new Padding(12)
                };
            }

            private void InitializeWatcher()
            {
                try
                {
                    string dir = AppDomain.CurrentDomain.BaseDirectory;
                    string queueFile = Path.Combine(dir, "download_queue.json");
                    if (!File.Exists(queueFile))
                    {
                        File.WriteAllText(queueFile, "[]");
                    }

                    queueWatcher = new FileSystemWatcher(dir, "download_queue.json")
                    {
                        NotifyFilter = NotifyFilters.LastWrite | NotifyFilters.Size | NotifyFilters.FileName,
                        EnableRaisingEvents = true
                    };

                    queueWatcher.Changed += (s, e) =>
                    {
                        Thread.Sleep(300);
                        this.BeginInvoke(new Action(CheckDownloadQueue));
                    };
                }
                catch (Exception ex)
                {
                    Debug.WriteLine("Queue watcher init error: " + ex.Message);
                }
            }

            private void CheckDownloadQueue()
            {
                if (!chkAutoWatch.Checked || isDownloading) return;

                try
                {
                    string queueFile = Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "download_queue.json");
                    if (!File.Exists(queueFile)) return;

                    string content = "";
                    using (var fs = new FileStream(queueFile, FileMode.Open, FileAccess.Read, FileShare.ReadWrite))
                    using (var reader = new StreamReader(fs))
                    {
                        content = reader.ReadToEnd();
                    }

                    if (string.IsNullOrEmpty(content) || content.Trim() == "[]") return;

                    var queue = jsonSerializer.Deserialize<List<Dictionary<string, object>>>(content);
                    if (queue == null || queue.Count == 0) return;

                    Dictionary<string, object> targetItem = null;

                    for (int i = 0; i < queue.Count; i++)
                    {
                        var itm = queue[i];
                        string url = (itm != null && itm.ContainsKey("url") && itm["url"] != null) ? itm["url"].ToString() : "";
                        if (!string.IsNullOrEmpty(url) && !processedUrls.Contains(url))
                        {
                            targetItem = itm;
                            break;
                        }
                    }

                    if (targetItem != null)
                    {
                        string songUrl = targetItem["url"].ToString();
                        string songFmt = (targetItem.ContainsKey("format") && targetItem["format"] != null) ? targetItem["format"].ToString() : "wav";
                        processedUrls.Add(songUrl);

                        this.WindowState = FormWindowState.Normal;
                        this.BringToFront();
                        this.Activate();

                        txtUrl.Text = songUrl;
                        StartDownload(songUrl, songFmt);
                    }
                }
                catch (Exception ex)
                {
                    Debug.WriteLine("Queue process notice: " + ex.Message);
                }
            }

            private string ExtractClipId(string input)
            {
                if (string.IsNullOrEmpty(input)) return "";
                var m = Regex.Match(input, @"[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}", RegexOptions.IgnoreCase);
                return m.Success ? m.Value : "";
            }

            private async void InspectSong(string inputUrl)
            {
                string clipId = ExtractClipId(inputUrl);
                if (string.IsNullOrEmpty(clipId))
                {
                    lblStatus.Text = "⚠️ សូមបញ្ចូល Link URL ឬ UUID របស់បទចម្រៀង Suno អោយបានត្រឹមត្រូវ។";
                    lblStatus.ForeColor = Color.Orange;
                    return;
                }

                lblStatus.Text = "🔍 កំពុងទាញយកព័ត៌មានបទចម្រៀង...";
                lblStatus.ForeColor = Color.FromArgb(100, 200, 255);

                await Task.Run(() =>
                {
                    try
                    {
                        using (WebClient wc = new WebClient())
                        {
                            wc.Headers.Add("User-Agent", "Mozilla/5.0 (Windows NT 10.0; Win64; x64)");
                            wc.Encoding = Encoding.UTF8;
                            string json = wc.DownloadString("https://studio-api.prod.suno.com/api/clip/" + clipId);
                            var data = jsonSerializer.Deserialize<Dictionary<string, object>>(json);

                            string title = (data != null && data.ContainsKey("title") && data["title"] != null) ? data["title"].ToString() : "Suno Song";
                            string status = (data != null && data.ContainsKey("status") && data["status"] != null) ? data["status"].ToString() : "unknown";
                            string durationStr = "";
                            if (data != null && data.ContainsKey("metadata") && data["metadata"] is Dictionary<string, object>)
                            {
                                var meta = (Dictionary<string, object>)data["metadata"];
                                if (meta != null && meta.ContainsKey("duration"))
                                {
                                    double sec = Convert.ToDouble(meta["duration"]);
                                    durationStr = string.Format("{0:D2}:{1:D2}", (int)sec / 60, (int)sec % 60);
                                }
                            }
                            string imgUrl = (data != null && data.ContainsKey("image_large_url") && data["image_large_url"] != null) ? data["image_large_url"].ToString() : "";

                            this.BeginInvoke(new Action(() =>
                            {
                                lblSongTitle.Text = title;
                                lblSongMeta.Text = string.Format("រយៈពេល៖ {0} | ស្ថានភាព៖ {1} | ID: {2}", durationStr, status, clipId);
                                lblStatus.Text = "✅ បានរកឃើញបទចម្រៀង! ចុច 'ទាញយកចម្រៀង' ដើម្បីទាញយក។";
                                lblStatus.ForeColor = Color.FromArgb(80, 230, 160);

                                if (!string.IsNullOrEmpty(imgUrl))
                                {
                                    try { picCover.LoadAsync(imgUrl); } catch { }
                                }
                            }));
                        }
                    }
                    catch (Exception ex)
                    {
                        this.BeginInvoke(new Action(() =>
                        {
                            lblStatus.Text = "⚠️ មិនអាចទាញយកព័ត៌មានពី Suno: " + ex.Message;
                            lblStatus.ForeColor = Color.Orange;
                        }));
                    }
                });
            }

            private async void StartDownload(string inputUrl, string format)
            {
                if (isDownloading) return;

                string clipId = ExtractClipId(inputUrl);
                if (string.IsNullOrEmpty(clipId))
                {
                    MessageBox.Show("សូមបញ្ចូល Link URL របស់ Suno អោយបានត្រឹមត្រូវ!\n(ឧ. https://suno.com/song/c9505feb-5492-400b-9648-c8af417b24eb)", "Suno Downloader", MessageBoxButtons.OK, MessageBoxIcon.Warning);
                    return;
                }

                isDownloading = true;
                btnDownload.Enabled = false;
                progressBar.Value = 10;
                lblStatus.Text = "⏳ កំពុងដំណើរការទាញយកសម្លេងពី Suno...";
                lblStatus.ForeColor = Color.FromArgb(255, 180, 60);

                string saveDir = txtSavePath.Text.Trim();
                if (!Directory.Exists(saveDir)) Directory.CreateDirectory(saveDir);

                await Task.Run(async () =>
                {
                    try
                    {
                        string title = "Suno_Song";
                        string durationStr = "0:00";
                        string imgUrl = "";

                        try
                        {
                            using (WebClient wc = new WebClient())
                            {
                                wc.Headers.Add("User-Agent", "Mozilla/5.0");
                                wc.Encoding = Encoding.UTF8;
                                string json = wc.DownloadString("https://studio-api.prod.suno.com/api/clip/" + clipId);
                                var data = jsonSerializer.Deserialize<Dictionary<string, object>>(json);
                                if (data != null && data.ContainsKey("title") && data["title"] != null) title = data["title"].ToString();
                                if (data != null && data.ContainsKey("image_large_url") && data["image_large_url"] != null) imgUrl = data["image_large_url"].ToString();
                                if (data != null && data.ContainsKey("metadata") && data["metadata"] is Dictionary<string, object>)
                                {
                                    var meta = (Dictionary<string, object>)data["metadata"];
                                    if (meta != null && meta.ContainsKey("duration"))
                                    {
                                        double sec = Convert.ToDouble(meta["duration"]);
                                        durationStr = string.Format("{0:D2}:{1:D2}", (int)sec / 60, (int)sec % 60);
                                    }
                                }
                            }
                        }
                        catch { }

                        this.BeginInvoke(new Action(() =>
                        {
                            lblSongTitle.Text = title;
                            if (!string.IsNullOrEmpty(imgUrl)) { try { picCover.LoadAsync(imgUrl); } catch { } }
                            progressBar.Value = 30;
                            lblStatus.Text = "⏳ កំពុងទាញយក Master Audio Stream...";
                        }));

                        string masterAudioUrl = "";
                        if (hiddenWebView != null && hiddenWebView.CoreWebView2 != null)
                        {
                            var tcs = new TaskCompletionSource<string>();
                            EventHandler<CoreWebView2WebMessageReceivedEventArgs> msgHandler = null;
                            msgHandler = (s, e) =>
                            {
                                try
                                {
                                    var res = jsonSerializer.Deserialize<Dictionary<string, object>>(e.WebMessageAsJson);
                                    if (res != null && res.ContainsKey("url") && res["url"] != null)
                                    {
                                        hiddenWebView.CoreWebView2.WebMessageReceived -= msgHandler;
                                        tcs.TrySetResult(res["url"].ToString());
                                    }
                                    else if (res != null && res.ContainsKey("error"))
                                    {
                                        hiddenWebView.CoreWebView2.WebMessageReceived -= msgHandler;
                                        tcs.TrySetResult("");
                                    }
                                }
                                catch { }
                            };

                            hiddenWebView.CoreWebView2.WebMessageReceived += msgHandler;

                            string script = string.Format(@"(async () => {{
                                try {{
                                    let token = null;
                                    if (window.Clerk && window.Clerk.session) {{
                                        token = await window.Clerk.session.getToken();
                                    }}
                                    const headers = token ? {{ 'Authorization': 'Bearer ' + token }} : {{}};
                                    const resp = await fetch('https://suno.com/a/api/download/clip/{0}?format=mp3', {{
                                        headers: headers,
                                        credentials: 'include'
                                    }});
                                    window.chrome.webview.postMessage({{ status: resp.status, url: resp.url }});
                                }} catch (err) {{
                                    window.chrome.webview.postMessage({{ error: err.message }});
                                }}
                            }})();", clipId);

                            this.BeginInvoke(new Action(async () =>
                            {
                                try { await hiddenWebView.CoreWebView2.ExecuteScriptAsync(script); } catch { tcs.TrySetResult(""); }
                            }));

                            var completedTask = await Task.WhenAny(tcs.Task, Task.Delay(8000));
                            if (completedTask == tcs.Task)
                            {
                                masterAudioUrl = await tcs.Task;
                            }
                        }

                        if (string.IsNullOrEmpty(masterAudioUrl) || masterAudioUrl.Contains("forbidden") || masterAudioUrl.Contains("/a/api/download"))
                        {
                            masterAudioUrl = string.Format("https://cdn1.suno.ai/{0}.mp3", clipId);
                        }

                        string tempAudio = Path.Combine(Path.GetTempPath(), string.Format("suno_{0}_{1}.mp3", clipId, DateTime.UtcNow.Ticks));
                        using (WebClient dlClient = new WebClient())
                        {
                            dlClient.Headers.Add("User-Agent", "Mozilla/5.0 (Windows NT 10.0; Win64; x64)");
                            dlClient.DownloadFile(masterAudioUrl, tempAudio);
                        }

                        this.BeginInvoke(new Action(() =>
                        {
                            progressBar.Value = 70;
                            lblStatus.Text = (format == "wav") ? "⚙️ កំពុងបំលែងទៅជា 16-bit 44.1kHz Stereo WAV (PCM)..." : "💾 កំពុងរក្សាទុកឯកសារ MP3...";
                        }));

                        string cleanTitle = Regex.Replace(title, @"[/\\?%*:|""<>]", "_").Trim();
                        if (string.IsNullOrEmpty(cleanTitle)) cleanTitle = "Suno_Song_" + clipId.Substring(0, 8);

                        string finalExt = (format == "wav") ? ".wav" : ".mp3";
                        string finalPath = Path.Combine(saveDir, cleanTitle + finalExt);

                        int counter = 1;
                        while (File.Exists(finalPath))
                        {
                            finalPath = Path.Combine(saveDir, string.Format("{0} ({1}){2}", cleanTitle, counter++, finalExt));
                        }

                        if (format == "wav")
                        {
                            string ffmpegArgs = string.Format("-i \"{0}\" -c:a pcm_s16le -ar 44100 -ac 2 \"{1}\" -y", tempAudio, finalPath);
                            ProcessStartInfo psi = new ProcessStartInfo(ffmpegPath, ffmpegArgs)
                            {
                                CreateNoWindow = true,
                                UseShellExecute = false,
                                RedirectStandardError = true,
                                RedirectStandardOutput = true
                            };

                            var proc = Process.Start(psi);
                            proc.WaitForExit(15000);

                            if (!File.Exists(finalPath) || new FileInfo(finalPath).Length < 1000)
                            {
                                throw new Exception("FFmpeg conversion failed or output empty.");
                            }
                        }
                        else
                        {
                            File.Copy(tempAudio, finalPath, true);
                        }

                        try { if (File.Exists(tempAudio)) File.Delete(tempAudio); } catch { }

                        FileInfo fi = new FileInfo(finalPath);
                        string fileSizeStr = string.Format("{0:F2} MB", (double)fi.Length / (1024 * 1024));

                        this.BeginInvoke(new Action(() =>
                        {
                            progressBar.Value = 100;
                            lblStatus.Text = string.Format("🎉 ទាញយកបានជោគជ័យ! រក្សាទុកក្នុង៖ {0}", Path.GetFileName(finalPath));
                            lblStatus.ForeColor = Color.FromArgb(80, 230, 160);

                            var item = new ListViewItem(cleanTitle);
                            item.SubItems.Add(format.ToUpper());
                            item.SubItems.Add(fileSizeStr);
                            item.SubItems.Add(DateTime.Now.ToString("HH:mm:ss"));
                            item.SubItems.Add(finalPath);
                            item.Tag = finalPath;
                            lvHistory.Items.Insert(0, item);

                            try { System.Media.SystemSounds.Asterisk.Play(); } catch { }
                        }));
                    }
                    catch (Exception ex)
                    {
                        this.BeginInvoke(new Action(() =>
                        {
                            progressBar.Value = 0;
                            lblStatus.Text = "⚠️ បរាជ័យក្នុងការទាញយក៖ " + ex.Message;
                            lblStatus.ForeColor = Color.OrangeRed;
                            MessageBox.Show("បរាជ័យក្នុងការទាញយកបទចម្រៀង៖\n" + ex.Message, "Suno Downloader Error", MessageBoxButtons.OK, MessageBoxIcon.Error);
                        }));
                    }
                    finally
                    {
                        this.BeginInvoke(new Action(() =>
                        {
                            isDownloading = false;
                            btnDownload.Enabled = true;
                        }));
                    }
                });
            }

            private void PlaySelectedFile()
            {
                if (lvHistory.SelectedItems.Count > 0)
                {
                    string path = lvHistory.SelectedItems[0].Tag as string;
                    if (!string.IsNullOrEmpty(path) && File.Exists(path))
                    {
                        try { Process.Start(new ProcessStartInfo(path) { UseShellExecute = true }); } catch { }
                    }
                }
            }

            private void OpenSelectedFolder()
            {
                if (lvHistory.SelectedItems.Count > 0)
                {
                    string path = lvHistory.SelectedItems[0].Tag as string;
                    if (!string.IsNullOrEmpty(path) && File.Exists(path))
                    {
                        try { Process.Start("explorer.exe", string.Format("/select,\"{0}\"", path)); } catch { }
                        return;
                    }
                }

                try { Process.Start("explorer.exe", txtSavePath.Text); } catch { }
            }
        }
    }
}
