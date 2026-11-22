# 🎵 Suno AI Studio Pro — Desktop Suite

ស្ទូឌីយោបង្កើតចម្រៀងឆ្លាតវៃ AI កម្រិតអាជីព (All-in-One AI Music Creation, Automation, Download & Media Management Suite) ដំណើរការលើ Windows 11/10។

[![GitHub Stars](https://img.shields.io/badge/Release-v3.5%20Pro-orange.svg)](https://github.com/vanndatree98)
[![Platform](https://img.shields.io/badge/Platform-Windows%20Desktop-blue.svg)](https://microsoft.com)
[![License](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)

---

## 🌟 លក្ខណៈពិសេសចម្បង (Key Features)

### 🚀 ១. ម៉ាស៊ីនបង្កើតចម្រៀង (AI Generation Engines)
* **🌐 Suno Chrome Studio (`SunoChrome.ps1`)**៖ ដំណើរការលើ Google Chrome Native Engine រំលង hCaptcha / Cloudflare Turnstile យ៉ាងរលូន ១០០% ដោយគ្មានបញ្ហា CSP Block តាមរយៈ Chrome Extension MV3 និង Local IPC Bridge (Port 48999)។
* **⚡ Suno Electron Native Desktop (`Suno.exe`)**៖ កម្មវិធីកុំព្យូទ័រ Desktop ដើម (High Performance) បង្កប់ដោយ Suno Studio Topbar, ជួរបញ្ជា Queue IPC, និងស្ទីលទំនើប។
* **🖥️ Suno WebView2 Studio (`SunoApp.ps1`)**៖ ម៉ាស៊ីន Windows WebView2 បង្កប់ក្នុង WinForms ជាមួយរបារឧបករណ៍ចម្រុះ និងប្រព័ន្ធទាញយកចម្រៀងស្វ័យប្រវត្តិ។

### 🎨 ២. ឧបករណ៍ជំនួយការនិពន្ធ AI (AI Creative Suite)
* **🌟 Suno Studio Central Hub (`SunoHub.ps1`)**៖ ផ្ទាំងបញ្ជា Master Dashboard គ្រប់គ្រងកម្មវិធីទាំងអស់ក្នុងកន្លែងតែមួយ។
* **✍️ Suno AI Lyric Composer (`SunoComposerApp.ps1`)**៖ ស្ទូឌីយោនិពន្ធទំនុកច្រៀង បង្កើត Prompt តាមរចនាបថ និងបញ្ជូន Auto-queue ទៅក្នុង Suno ដោយស្វ័យប្រវត្តិ។
* **🎨 Suno Theme Selector (`SunoThemeSelector.ps1`)**៖ ផ្លាស់ប្តូរពណ៌ Theme កម្មវិធី Suno (Dark Studio, Cyberpunk, Midnight Neon, Sunset, Forest) សម្រាប់ផ្ទាំងបញ្ជា។
* **🤖 Gemini AI Title Generator (`GeminiTitleGenerator.ps1`)**៖ បង្កើតចំណងជើងបទចម្រៀងពីរោះៗ ភាសាខ្មែរ/អន្តរជាតិ រៀបចំជា Playlist ដោយប្រើប្រាស់ Gemini AI ទំនើប។
* **🧪 Suno Prompt Laboratory (`SunoPromptStudio.ps1`)**៖ មន្ទីរពិសោធន៍បង្កើត Music Style Prompt តាមរចនាបថតន្ត្រី ឧបករណ៍ បរិយាកាស និងគុណភាពផលិត។
* **✍️ Suno Rhyme & Lyrics Lab (`SunoRhymeStudio.ps1`)**៖ រៀបចំរចនាសម្ព័ន្ធទំនុកច្រៀង បញ្ចូល Suno Metatags (`[Chorus]`, `[Drop]`, `[Bridge]`) និងផ្ទៀងផ្ទាត់ចង្វាក់ពាក្យជួន។

### 🎵 ៣. គ្រប់គ្រង និងទាញយកចម្រៀង (Media & Downloads)
* **🎵 Suno Audio Studio (`SunoAudioStudio.ps1`)**៖ ស្ទូឌីយោចាក់ស្តាប់បទចម្រៀង (Native WPF MediaPlayer) កែប្រែព័ត៌មានបទ (Title/Artist) និងរៀបចំបញ្ជីបទចម្រៀង។
* **🎛️ Suno Audio Converter (`SunoAudioConverter.ps1`)**៖ បំប្លែងទម្រង់ឯកសារចម្រៀង (WAV, MP3, FLAC, AAC), កាត់បន្ថយសំឡេងស្ងាត់ដើម/ចុង និង Normalize Loudness តាមស្តង់ដារ Streaming (-14 LUFS) ដោយប្រើ FFmpeg។
* **📥 Suno WAV Batch Downloader (`SunoDownloader.ps1`)**៖ ទាញយកឯកសារចម្រៀង WAV/MP3 គុណភាពខ្ពស់បំផុតពី Suno ដោយផ្ទាល់។
* **📦 Suno Playlist Downloader (`SunoPlaylistDownloader.ps1`)**៖ ទាញយកចម្រៀងទាំងមូលពី Playlist ខ្ចប់ជាកញ្ចប់ ZIP និងទាញយកដោយស្វ័យប្រវត្តិតាមជួរ Queue។

### 🛠️ ៤. ឧបករណ៍ថែទាំ និងសុវត្ថិភាពប្រព័ន្ធ (System Utilities)
* **🩺 Suno System Doctor (`SunoDoctor.ps1`)**៖ ស្កេនពិនិត្យប្រព័ន្ធ រកមើលចំណុចខ្វះខាត និងជួសជុលស្វ័យប្រវត្តិកម្រិតខ្ពស់ ៨ ចំណុចគ្រឹះ (Self-Healing Engine)។
* **📦 Suno Backup Manager (`SunoBackupManager.ps1`)**៖ បង្កើតកញ្ចប់ Backup និងស្ដារទិន្នន័យចល័ត Data ទាំងមូល (Sessions, Logins, Downloads) ដោយចុចតែ ១ ដង។
* **⚡ Suno Quick HUD Widget (`SunoQuickHUD.ps1`)**៖ ផ្ទាំង Dashboard អណ្តែតលើអេក្រង់កុំព្យូទ័រ (Always-On-Top Desktop Widget) សម្រាប់បញ្ជាកិច្ចការលឿនៗ។
* **🐙 Suno GitHub Cloud Sync (`SunoGitHubSync.ps1`)**៖ ធ្វើសមកាលកម្មកូដ និងគម្រោងទាំងមូលឡើងទៅកាន់ GitHub Repository ដោយចុចតែ ១ ដង។

---

## 📁 រចនាសម្ព័ន្ធថតឯកសារ (Architecture & Directory Structure)

```text
Programs\Suno\
├── Data\                                  <-- ថតប្រមូលផ្តុំទិន្នន័យចល័ត ១០០% (Portable Data)
│   ├── ChromeUserData\                    <-- ទិន្នន័យ Chrome Session, Cookies & Profile
│   ├── UserData\                          <-- ទិន្នន័យ WebView2 Desktop Profile
│   ├── ElectronUserData\                  <-- ទិន្នន័យ Electron Native Desktop Profile
│   └── Downloads\                         <-- ថតចម្រៀងទាញយករួច (MP3, WAV, ZIP)
├── Backups\                               <-- ថតកញ្ចប់ Backup .ZIP ស្វ័យប្រវត្តិ
├── chrome_extension\                      <-- Chrome MV3 Extension (Bypass Cloudflare & Port 48999 Bridge)
│   ├── manifest.json
│   ├── studio.js                          <-- In-sync ជាមួយ root studio.js
│   └── studio_bridge.js
├── SunoHub.ps1 / SunoHub.bat              <-- 🌟 Central Master Hub Dashboard
├── SunoDoctor.ps1 / SunoDoctor.bat        <-- 🩺 System Doctor & Self-Healing
├── SunoAudioStudio.ps1 / .bat             <-- 🎵 Audio Player & Metadata Studio
├── SunoPromptStudio.ps1 / .bat            <-- 🧪 Music Style Prompt Laboratory
├── SunoBackupManager.ps1 / .bat           <-- 📦 Portable Backup & Restore Manager
├── SunoChrome.ps1 / SunoChrome.bat        <-- 🌐 Google Chrome Engine Launcher
├── SunoApp.ps1 / Suno.bat / Suno.exe      <-- ⚡ Desktop Apps (WebView2 & Electron)
├── SunoComposerApp.ps1 / .bat             <-- ✍️ AI Lyric Composer & Prompter
├── SunoThemeSelector.ps1 / .bat           <-- 🎨 Studio Theme Selector
├── SunoDownloader.ps1 / .bat              <-- 📥 WAV Downloader
├── SunoPlaylistDownloader.ps1 / .bat      <-- 📦 Playlist Downloader
└── GeminiTitleGenerator.ps1 / .bat        <-- 🤖 Gemini AI Title Generator
```

---

## 🚀 របៀបដំឡើង និងដំណើរការ (Quick Start)

### ១. តម្រូវការប្រព័ន្ធ (Prerequisites)
* Windows 10 ឬ Windows 11 (64-bit)
* PowerShell 5.1 ឬ PowerShell 7+
* Google Chrome (សម្រាប់ដំណើរការម៉ាស៊ីន Chrome Studio)
* Node.js v18+ (សម្រាប់ Engine Playlist Downloader)

### ២. ដំណើរការកម្មវិធី
1. បើកដំណើរការ **`Suno Studio Central Hub.lnk`** នៅលើ Desktop ដើម្បីគ្រប់គ្រងកម្មវិធីទាំងអស់។
2. ឬចុចពីរដងលើ **`Suno AI Studio (Google Chrome).lnk`** ដើម្បីចាប់ផ្តើមបង្កើតចម្រៀងដោយរំលង Cloudflare Turnstile ដោយស្វ័យប្រវត្តិ។

---

## 👨‍💻 អ្នកអភិវឌ្ឍន៍ (Developer)

* **GitHub**: [@vanndatree98](https://github.com/vanndatree98)
* **Project**: Suno AI Studio Pro Suite
