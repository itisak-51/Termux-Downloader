#!/data/data/com.termux/files/usr/bin/bash
# ============================================================================
#  Downloader.sh - Resumable downloader for links.txt or Google Drive items
#  Now supports: single files, folders (recursive), and plain link lists.
#  Interactive file selection + confirmation with name/size.
# ============================================================================

DOWNLOAD_DIR="/sdcard/Download/TD_Downloads"
ARIA2_TEMP_DIR=".aria2_control"
LOG_FILE="log.txt"
GDRIVE_TOKEN_FILE="gdrive_token.pickle"
GDRIVE_CREDENTIALS_FILE="credentials.json"

mkdir -p "$DOWNLOAD_DIR" "$ARIA2_TEMP_DIR"

# ----------------------------- Helper Functions ---------------------------
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
}

human_size() {
    local bytes=$1
    if (( bytes >= 1073741824 )); then
        local gb=$(( bytes / 1073741824 ))
        local rem=$(( bytes % 1073741824 ))
        local frac=$(( (rem * 10) / 1073741824 ))
        printf "%d.%d GB" "$gb" "$frac"
    elif (( bytes >= 1048576 )); then
        local mb=$(( bytes / 1048576 ))
        local rem=$(( bytes % 1048576 ))
        local frac=$(( (rem * 10) / 1048576 ))
        printf "%d.%d MB" "$mb" "$frac"
    elif (( bytes >= 1024 )); then
        local kb=$(( bytes / 1024 ))
        local rem=$(( bytes % 1024 ))
        local frac=$(( (rem * 10) / 1024 ))
        printf "%d.%d KB" "$kb" "$frac"
    else
        printf "%d B" "$bytes"
    fi
}

download_with_aria2() {
    local url="$1"
    local filename="$2"
    local relative_path="$3"   # e.g. "subfolder/file.zip"

    # Create subdirectory if needed
    if [[ -n "$relative_path" && "$relative_path" != "$filename" ]]; then
        local dir_part="${relative_path%/*}"
        [[ "$dir_part" != "$relative_path" ]] && mkdir -p "$DOWNLOAD_DIR/$dir_part"
    fi

    local control_file="${ARIA2_TEMP_DIR}/$(echo -n "$url" | md5sum | cut -d' ' -f1).aria2"
    local full_output_path="$DOWNLOAD_DIR/$relative_path"

    log "Starting download: $relative_path"
    aria2c \
        --dir="$DOWNLOAD_DIR" \
        --out="$filename" \
        --continue=true \
        --max-connection-per-server=16 \
        --split=16 \
        --min-split-size=1M \
        --max-tries=0 \
        --retry-wait=5 \
        --conditional-get=true \
        --allow-overwrite=false \
        --auto-file-renaming=false \
        --console-log-level=error \
        --summary-interval=0 \
        --download-result=default \
        "$url"

    if [[ $? -eq 0 ]]; then
        # Move to correct subfolder if aria2c ignored subdirs
        if [[ -n "$relative_path" && "$relative_path" != "$filename" ]]; then
            mv "$DOWNLOAD_DIR/$filename" "$full_output_path" 2>/dev/null
        fi
        log "Success: $relative_path"
        rm -f "$control_file"
        return 0
    else
        log "FAILED: $relative_path (will retry when script is re-run)"
        return 1
    fi
}

# ----------------------------- Common interactive selection ----------------
select_files() {
    local index=$1
    printf "\n%4s  %-70s %10s\n" "No." "File" "Size"
    echo "------------------------------------------------------------------------------"
    for (( i=1; i<=index; i++ )); do
        local sz="?"
        [[ -n "${file_size[i]}" ]] && sz=$(human_size "${file_size[i]}")
        local display_name="${file_path[i]}"
        [[ -z "$display_name" ]] && display_name="${file_name[i]}"
        printf "%4d) %-70s %10s\n" "$i" "${display_name:0:70}" "$sz"
    done
    echo "------------------------------------------------------------------------------"

    echo ""
    echo "Enter file numbers to download (e.g., 1,3,5-7,12  or  all  or  none):"
    read -r selection
    selection=$(echo "$selection" | tr -d ' ')

    if [[ "$selection" == "none" || "$selection" == "" ]]; then
        log "Nothing selected. Exiting."
        exit 0
    fi

    local -a chosen_indices=()
    if [[ "$selection" == "all" ]]; then
        for (( i=1; i<=index; i++ )); do chosen_indices+=("$i"); done
    else
        IFS=',' read -ra parts <<< "$selection"
        for part in "${parts[@]}"; do
            if [[ "$part" =~ ^[0-9]+-[0-9]+$ ]]; then
                IFS='-' read -r start end <<< "$part"
                if (( start < 1 || end > index || start > end )); then
                    log "ERROR: Invalid range $start-$end. Exiting."
                    exit 1
                fi
                for (( i=start; i<=end; i++ )); do chosen_indices+=("$i"); done
            elif [[ "$part" =~ ^[0-9]+$ ]]; then
                local num=$part
                if (( num < 1 || num > index )); then
                    log "ERROR: Invalid number $num. Exiting."
                    exit 1
                fi
                chosen_indices+=("$num")
            else
                log "ERROR: Unrecognised selection '$part'. Exiting."
                exit 1
            fi
        done
    fi

    chosen_indices=($(printf "%d\n" "${chosen_indices[@]}" | sort -n | uniq))
    local total_chosen=${#chosen_indices[@]}

    echo ""
    log "You selected $total_chosen file(s) to download."
    echo "Proceed? (y/n)"
    read -r confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        log "Aborted by user."
        exit 0
    fi

    for idx in "${chosen_indices[@]}"; do
        download_with_aria2 "${file_url[$idx]}" "${file_name[$idx]}" "${file_path[$idx]}"
    done
}

# ----------------------------- Case 1: links.txt -------------------------
process_links_txt() {
    local input_file="$1"
    if [[ ! -f "$input_file" ]]; then
        log "ERROR: File '$input_file' not found."
        exit 1
    fi

    log "Reading URLs from $input_file"

    declare -a file_url file_name file_path file_size
    local index=0
    while IFS= read -r line; do
        [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue
        local url filename
        if [[ "$line" == *"|"* ]]; then
            url="${line%%|*}"
            filename="${line##*|}"
        else
            url="$line"
            filename=$(basename "$url" | sed 's/?.*//')
            [[ -z "$filename" ]] && filename="unknown_$(date +%s)"
        fi
        ((index++))
        file_url[index]="$url"
        file_name[index]="$filename"
        file_path[index]=""          # no subfolder for direct links
        file_size[index]=""
    done < "$input_file"

    if (( index == 0 )); then
        log "No valid URLs found in '$input_file'."
        exit 0
    fi

    select_files "$index"
}

# ----------------------------- Google Drive Lister (recursive) ------------
create_gdrive_lister() {
    cat > "$ARIA2_TEMP_DIR/gdrive_lister.py" << 'PYEOF'
import os
import pickle
import sys
from google.auth.transport.requests import Request
from google_auth_oauthlib.flow import InstalledAppFlow
from googleapiclient.discovery import build

SCOPES = ['https://www.googleapis.com/auth/drive.readonly']
TOKEN_FILE = os.path.expanduser('gdrive_token.pickle')
CRED_FILE = os.path.expanduser('credentials.json')

def get_authenticated_service():
    creds = None
    if os.path.exists(TOKEN_FILE):
        with open(TOKEN_FILE, 'rb') as token:
            creds = pickle.load(token)
    if not creds or not creds.valid:
        if creds and creds.expired and creds.refresh_token:
            creds.refresh(Request())
        else:
            if not os.path.exists(CRED_FILE):
                sys.stderr.write("ERROR: credentials.json not found.\n")
                sys.exit(1)
            flow = InstalledAppFlow.from_client_secrets_file(CRED_FILE, SCOPES)
            flow.redirect_uri = 'urn:ietf:wg:oauth:2.0:oob'
            auth_url, _ = flow.authorization_url(prompt='consent')
            sys.stderr.write(f"\n🔐 Authorize this app by visiting:\n{auth_url}\n\n")
            sys.stderr.write("After approval, enter the authorization code: ")
            code = input().strip()
            flow.fetch_token(code=code)
            creds = flow.credentials
        with open(TOKEN_FILE, 'wb') as token:
            pickle.dump(creds, token)
    return build('drive', 'v3', credentials=creds)

def list_recursive(service, folder_id, base_path=''):
    """
    Recursively list all files inside a folder. Returns a list of dicts:
    { 'id', 'name', 'size', 'relative_path' }
    """
    all_items = []
    page_token = None
    while True:
        results = service.files().list(
            q=f"'{folder_id}' in parents and trashed=false",
            fields="nextPageToken, files(id, name, mimeType, size)",
            pageToken=page_token,
            pageSize=1000
        ).execute()
        items = results.get('files', [])
        for item in items:
            mime = item.get('mimeType', '')
            name = item['name']
            rel = f"{base_path}/{name}" if base_path else name
            if mime == 'application/vnd.google-apps.folder':
                sub_items = list_recursive(service, item['id'], rel)
                all_items.extend(sub_items)
            else:
                all_items.append({
                    'id': item['id'],
                    'name': name,
                    'size': item.get('size', '0'),
                    'relative_path': rel
                })
        page_token = results.get('nextPageToken')
        if not page_token:
            break
    return all_items

if __name__ == '__main__':
    if len(sys.argv) != 2:
        sys.stderr.write("Usage: gdrive_lister.py <folder_id>\n")
        sys.exit(1)

    folder_id = sys.argv[1]
    try:
        service = get_authenticated_service()
        items = list_recursive(service, folder_id)
    except Exception as e:
        sys.stderr.write(f"Error listing files: {e}\n")
        sys.exit(1)

    if not items:
        sys.exit(0)

    for item in items:
        url = f"https://drive.usercontent.google.com/download?id={item['id']}&confirm=t"
        name = item['name']
        size = item['size']
        path = item['relative_path']
        print(f"{url}|{name}|{size}|{path}")
PYEOF
}

process_gdrive_folder() {
    local folder_url="$1"
    local folder_id=""

    if [[ "$folder_url" =~ /folders/([a-zA-Z0-9_-]+) ]]; then
        folder_id="${BASH_REMATCH[1]}"
    elif [[ "$folder_url" =~ id=([a-zA-Z0-9_-]+) ]]; then
        folder_id="${BASH_REMATCH[1]}"
    else
        log "ERROR: Invalid Google Drive folder URL"
        exit 1
    fi

    log "Fetching file list recursively from Google Drive folder ID: $folder_id"

    if ! python3 -c "import googleapiclient" 2>/dev/null; then
        log "Installing Google API client (first time only)..."
        pip install --upgrade google-api-python-client google-auth-oauthlib google-auth-httplib2
    fi

    create_gdrive_lister

    local lister_py="$ARIA2_TEMP_DIR/gdrive_lister.py"
    local queue_file="$ARIA2_TEMP_DIR/gdrive_queue.txt"

    if ! python3 "$lister_py" "$folder_id" > "$queue_file"; then
        log "Error running the Google Drive lister. Check the messages above."
        exit 1
    fi

    if [[ ! -s "$queue_file" ]]; then
        log "No files found in the folder (or folder is empty)."
        exit 0
    fi

    # Clear arrays before reading
    unset file_url file_name file_path file_size
    declare -a file_url file_name file_path file_size
    local index=0
    while IFS='|' read -r url name size path; do
        ((index++))
        file_url[index]="$url"
        file_name[index]="$name"
        file_size[index]="$size"
        file_path[index]="$path"
    done < "$queue_file"

    select_files "$index"
}

# ----------------------------- Single Google Drive file --------------------
process_gdrive_file() {
    local file_url="$1"
    local file_id=""

    # Extract file ID from various URL formats
    if [[ "$file_url" =~ /file/d/([a-zA-Z0-9_-]+) ]]; then
        file_id="${BASH_REMATCH[1]}"
    elif [[ "$file_url" =~ id=([a-zA-Z0-9_-]+) ]]; then
        file_id="${BASH_REMATCH[1]}"
    else
        log "ERROR: Invalid Google Drive file URL"
        exit 1
    fi

    log "Fetching info for Google Drive file ID: $file_id"

    # Ensure Google API client is installed (same as folder mode)
    if ! python3 -c "import googleapiclient" 2>/dev/null; then
        log "Installing Google API client (first time only)..."
        pip install --upgrade google-api-python-client google-auth-oauthlib google-auth-httplib2
    fi

    local info_py="$ARIA2_TEMP_DIR/gdrive_file_info.py"
    cat > "$info_py" << 'PYEOF'
import os
import pickle
import sys
from google.auth.transport.requests import Request
from google_auth_oauthlib.flow import InstalledAppFlow
from googleapiclient.discovery import build

SCOPES = ['https://www.googleapis.com/auth/drive.readonly']
TOKEN_FILE = os.path.expanduser('gdrive_token.pickle')
CRED_FILE = os.path.expanduser('credentials.json')

def get_authenticated_service():
    creds = None
    if os.path.exists(TOKEN_FILE):
        with open(TOKEN_FILE, 'rb') as token:
            creds = pickle.load(token)
    if not creds or not creds.valid:
        if creds and creds.expired and creds.refresh_token:
            creds.refresh(Request())
        else:
            if not os.path.exists(CRED_FILE):
                sys.stderr.write("ERROR: credentials.json not found.\n")
                sys.exit(1)
            flow = InstalledAppFlow.from_client_secrets_file(CRED_FILE, SCOPES)
            flow.redirect_uri = 'urn:ietf:wg:oauth:2.0:oob'
            auth_url, _ = flow.authorization_url(prompt='consent')
            sys.stderr.write(f"\n🔐 Authorize this app by visiting:\n{auth_url}\n\n")
            sys.stderr.write("After approval, enter the authorization code: ")
            code = input().strip()
            flow.fetch_token(code=code)
            creds = flow.credentials
        with open(TOKEN_FILE, 'wb') as token:
            pickle.dump(creds, token)
    return build('drive', 'v3', credentials=creds)

if __name__ == '__main__':
    if len(sys.argv) != 2:
        sys.stderr.write("Usage: gdrive_file_info.py <file_id>\n")
        sys.exit(1)
    file_id = sys.argv[1]
    try:
        service = get_authenticated_service()
        file_meta = service.files().get(fileId=file_id, fields="name,size").execute()
        name = file_meta.get('name', 'unknown')
        size = file_meta.get('size', '0')
        print(f"{name}|{size}")
    except Exception as e:
        sys.stderr.write(f"Error: {e}\n")
        sys.exit(1)
PYEOF

    local info_file="$ARIA2_TEMP_DIR/file_info.txt"
    if ! python3 "$info_py" "$file_id" > "$info_file" 2>&1; then
        log "Failed to get file info. Check error messages:"
        cat "$info_file"
        exit 1
    fi

    IFS='|' read -r file_name file_size < "$info_file"
    log "File: $file_name"
    log "Size: $(human_size "$file_size")"

    echo ""
    echo "Do you want to download this file? (y/n)"
    read -r confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        log "Aborted by user."
        exit 0
    fi

    # Build direct download URL (confirm=t bypasses the warning page)
    local download_url="https://drive.usercontent.google.com/download?id=$file_id&confirm=t"

    download_with_aria2 "$download_url" "$file_name" "$file_name"
}

# ----------------------------- Main -----------------------------
main() {
    if [[ $# -lt 1 ]]; then
        echo "Usage: $0 <links.txt | google_drive_folder_url | google_drive_file_url>"
        echo ""
        echo "Examples:"
        echo "  $0 links.txt"
        echo "  $0 https://drive.google.com/drive/folders/1ABC123"
        echo "  $0 https://drive.google.com/file/d/1XYZ789/view"
        exit 1
    fi

    input="$1"
    if [[ -f "$input" ]]; then
        process_links_txt "$input"
    elif [[ "$input" =~ drive.google.com.*folders ]]; then
        process_gdrive_folder "$input"
    elif [[ "$input" =~ drive.google.com.*file/d/ ]]; then
        process_gdrive_file "$input"
    else
        echo "ERROR: '$input' is neither an existing file nor a Google Drive folder/file link."
        exit 1
    fi

    log "All operations completed. Files are in '$DOWNLOAD_DIR'"
}

set +e
main "$@"
exit 0
