# Downloader.sh

**Resumable file downloader for Termux on Android (or any Linux system)**  
Supports direct URLs from a `links.txt` file **and** entire Google Drive folders with interactive file selection.

- ✅ Resumes interrupted downloads automatically (uses `aria2c`)
- ✅ Lists files with size before downloading
- ✅ Pick files individually, by range, or all/none
- ✅ Works without a browser on headless or Android/Termux environments
- ✅ Single self-contained script – no manual Python editing required

---

## Requirements

Inside Termux, run:

```bash
pkg update -y
pkg upgrade -y
pkg install aria2 rust python python-cryptography git -y
```

Then install the required Python libraries:

```bash
pip install --upgrade google-api-python-client google-auth-oauthlib google-auth-httplib2
```

*(If you are on a standard Linux distribution, use your package manager to install `aria2`, `python3`, `python3-pip`, and then run the pip command above.)*

---

## Installation

1. **Clone the repository**:
   ```bash
   git clone https://github.com/itisak-51/Termux-Downloader.git
   cd Termux-Downloader
   ```
   *(Or simply download `Downloader.sh` to your device.)*

2. **Make the script executable**:
   ```bash
   chmod +x Downloader.sh
   ```

---

## Google Drive Setup (required only for folders)

To download from a Google Drive folder, the script needs read-only access. You’ll create an OAuth 2.0 Desktop client in the Google Cloud Console.

### Step‑by‑step: Obtaining `credentials.json`

1. Go to the [Google Cloud Console](https://console.cloud.google.com/).
2. Create a new project (or select an existing one):
   - Click the project dropdown at the top → **New Project** → give it a name → **Create**.
3. **Enable the Google Drive API**:
   - Navigate to **APIs & Services** → **Library**.
   - Search for *Google Drive API*, click it, and click **Enable**.
4. **Configure the OAuth consent screen**:
   - In **APIs & Services**, go to **OAuth consent screen**.
   - Select **External** (or Internal if you’re inside a Google Workspace domain; External works for personal accounts).
   - Fill in the required fields:
     - **App name** – e.g., *Termux Downloader*.
     - **User support email** – your email.
     - **Developer contact information** – your email.
   - Click **Save and Continue**. Skip the scopes and test users pages (just save).
5. **Create OAuth credentials**:
   - In **Credentials**, click **+ Create Credentials** → **OAuth client ID**.
   - Choose **Desktop app** as the application type.
   - Give it a name (e.g., `Termux Downloader`) and click **Create**.
6. **Download the JSON file**:
   - After creation, a pop‑up appears with your client ID. Click **Download JSON**.
   - Rename the downloaded file to exactly `credentials.json`.
7. **Place the file in your home directory**:
   - In Termux, your home is `/data/data/com.termux/files/home/`.  
   - Move or copy `credentials.json` there.  
     Example:
     ```bash
     mv /sdcard/Download/credentials.json ~/Termux-Downloader
     ```

> **Important**: Keep `credentials.json` private – it allows access to your Drive.

---

## Usage

### 1. Download from a `links.txt` file

Create a text file with one direct URL per line. Optionally, add a custom filename separated by `|`. Lines beginning with `#` are ignored.

**Example `links.txt`:**
```
https://example.com/file1.zip
https://example.com/file2.mp4|MyVideo.mp4
# This is a comment
```

Then run:

```bash
./Downloader.sh links.txt
```

### 2. Download from a Google Drive folder

Use the folder’s shareable link (the folder must be viewable by “Anyone with the link”, or you must be signed in with the same Google account used for OAuth).

```bash
./Downloader.sh "https://drive.google.com/drive/folders/1ABC123..."
```

**What happens:**

- If no valid token exists, the script will display a URL.  
  **Open it in your phone’s browser**, approve the access, and you will be given an authorisation code.  
  Copy that code and paste it into Termux.
- A table of files appears, showing **index numbers**, **filenames**, and **sizes**.
- You are asked to **select files** to download.  
  Examples:
  - `1,3,5-7,12` – downloads those specific files
  - `all` – downloads everything
  - `none` – exits without downloading
- Confirm with `y` and the downloads begin.

### 3. Resume interrupted downloads

If a download is interrupted (e.g., connection drops, you press `Ctrl+C`), simply run the **exact same command** again. `aria2c` automatically resumes from where it left off.

---

## File Overview

| File / Folder | Purpose |
|---------------|---------|
| `Downloader.sh` | Main script (place and run this) |
| `.aria2_control/` | Temporary folder – control files and auto‑generated Python helper |
| `log.txt` | Detailed download log (created in the same directory) |
| `/sdcard/Download/TD_Downloads/` | Default download location (configurable inside the script) |
| `credentials.json` | OAuth credentials (you must obtain this yourself) |
| `gdrive_token.pickle` | Cached authorisation token (generated after first successful auth) |

---

## Troubleshooting

| Problem | Solution |
|---------|----------|
| `credentials.json not found` | Ensure the file is in your home directory (`~/credentials.json`). |
| OAuth error: “Missing required parameter: redirect_uri” | Delete `gdrive_token.pickle` (`rm ~/gdrive_token.pickle`) and re‑run. The script now uses the correct out‑of‑band flow. |
| `python3: command not found` or missing Google libraries | Run the `pkg install` and `pip install` commands from the **Requirements** section. |
| No files found in folder | The folder may be empty, or you don’t have access. Ensure the folder is shared with the same Google account used for OAuth. |
| “Failed to resolve host” during download | Check your internet connection. `aria2c` will retry automatically when you re‑run the script. |

---

## Notes

- The script is built primarily for **Termux on Android**, but works on any Linux environment with `aria2`, `python3`, and the Google API libraries.
- The OAuth token is cached in `gdrive_token.pickle` – you will not need to re‑authenticate until it expires (usually after a long time).
- The `links.txt` mode does **not** show an interactive file list; it downloads every URL listed.

---

## License

This project is provided as‑is for personal use. Feel free to modify and share.
