#!/usr/bin/env python3
"""Google Drive file/folder downloader with 3-tier auth strategy.

Usage:
    gdrive-download.py [--output-dir DIR] <URL_or_FILE_ID_or_FOLDER_URL>

Output:
    Prints downloaded file path(s) to stdout on success (one per line)
    Prints errors to stderr

Exit codes:
    0 - Success
    1 - Error
"""

import sys
import os
import json
import time
import re
import urllib.request
import urllib.parse
import urllib.error
from datetime import datetime, timezone
from pathlib import Path
from typing import Optional, Tuple, Dict

# Constants
SA_KEY_PATH = Path("/root/workspaces/secrets/services/google/service-account.json")
OAUTH_TOKEN_PATH = Path("/root/workspaces/secrets/services/google/token.json")
REQUEST_TIMEOUT = 30
USER_AGENT = "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36"

# MIME type to export format mapping
EXPORT_FORMATS = {
    "application/vnd.google-apps.document": ("application/pdf", "pdf"),
    "application/vnd.google-apps.spreadsheet": ("application/vnd.openxmlformats-officedocument.spreadsheetml.sheet", "xlsx"),
    "application/vnd.google-apps.presentation": ("application/pdf", "pdf"),
    "application/vnd.google-apps.drawing": ("application/pdf", "pdf"),
}


def get_output_dir() -> Path:
    """Determine output directory with priority:
    1. --output-dir CLI argument (parsed in main())
    2. CLAUDE_DOWNLOAD_DIR environment variable
    3. .claude-downloads/ in project from /tmp/.project-dir-lock
    4. Fallback: /tmp/claude-gdrive/
    """
    # Priority 2: Environment variable
    env_dir = os.environ.get("CLAUDE_DOWNLOAD_DIR")
    if env_dir:
        return Path(env_dir)

    # Priority 3: Project directory from lock file
    lock_file = Path("/tmp/.project-dir-lock")
    if lock_file.exists():
        try:
            project_dir = lock_file.read_text().strip()
            if project_dir and Path(project_dir).is_dir():
                return Path(project_dir) / ".claude-downloads"
        except Exception:
            pass

    # Priority 4: Fallback
    return Path("/tmp/claude-gdrive")


def resolve_redirect(url: str, max_redirects: int = 5) -> str:
    """Follow HTTP redirects and return the final URL.

    Used to resolve short links (b244.ru, bit.ly, goo.gl, etc.)
    that may redirect to Google Drive.

    Args:
        url: The URL to resolve (may be a short link)
        max_redirects: Maximum number of redirects to follow

    Returns:
        Final URL after following all redirects, or original URL on failure
    """
    import http.client
    import urllib.parse

    current_url = url
    for _ in range(max_redirects):
        try:
            parsed = urllib.parse.urlparse(current_url)
            scheme = parsed.scheme.lower()
            host = parsed.netloc
            path = parsed.path or "/"
            if parsed.query:
                path = f"{path}?{parsed.query}"

            if scheme == "https":
                conn = http.client.HTTPSConnection(host, timeout=10)
            elif scheme == "http":
                conn = http.client.HTTPConnection(host, timeout=10)
            else:
                break

            conn.request("HEAD", path, headers={"User-Agent": USER_AGENT})
            resp = conn.getresponse()
            conn.close()

            if resp.status in (301, 302, 303, 307, 308):
                location = resp.getheader("Location", "")
                if not location:
                    break
                # Handle relative redirects
                if location.startswith("/"):
                    current_url = f"{scheme}://{host}{location}"
                elif not location.startswith("http"):
                    current_url = f"{scheme}://{host}/{location}"
                else:
                    current_url = location
            else:
                # No redirect — we have the final URL
                break
        except Exception as e:
            print(f"Redirect resolution error at {current_url}: {e}", file=sys.stderr)
            break

    return current_url


def extract_file_id(input_str: str) -> Optional[str]:
    """Extract Google Drive file ID from URL or return as-is if already an ID.

    Handles formats:
    - https://drive.google.com/file/d/FILE_ID/view
    - https://drive.google.com/open?id=FILE_ID
    - https://drive.google.com/d/FILE_ID/
    - FILE_ID (raw ID)
    """
    item_id, _ = extract_id_and_type(input_str)
    return item_id


def extract_id_and_type(input_str: str) -> Tuple[Optional[str], str]:
    """Extract Google Drive file/folder ID and type from URL or raw ID.

    Returns:
        (id, type) where type is 'file' or 'folder'
    """
    if not input_str:
        return None, 'file'

    # Already a raw ID (alphanumeric, dashes, underscores, 25-50 chars)
    if re.match(r'^[\w-]{25,50}$', input_str):
        return input_str, 'file'  # Assume file for raw IDs

    # Folder URL
    if '/folders/' in input_str:
        match = re.search(r'/folders/([^/?&#]+)', input_str)
        if match:
            return match.group(1), 'folder'

    # File URL patterns
    patterns = [
        r'/file/d/([^/]+)',
        r'/d/([^/]+)',
        r'[?&]id=([^&]+)',
    ]
    for pattern in patterns:
        match = re.search(pattern, input_str)
        if match:
            return match.group(1), 'file'

    return None, 'file'


def make_request(url: str, headers: Optional[Dict[str, str]] = None, data: Optional[bytes] = None) -> Tuple[bytes, Dict]:
    """Make HTTP request with proper error handling."""
    if headers is None:
        headers = {}

    if 'User-Agent' not in headers:
        headers['User-Agent'] = USER_AGENT

    req = urllib.request.Request(url, data=data, headers=headers)

    try:
        with urllib.request.urlopen(req, timeout=REQUEST_TIMEOUT) as response:
            return response.read(), dict(response.headers)
    except urllib.error.HTTPError as e:
        # Return error body for debugging
        error_body = e.read() if hasattr(e, 'read') else b''
        return error_body, {'status': e.code, 'reason': e.reason}
    except urllib.error.URLError as e:
        raise Exception(f"Network error: {e.reason}")


def download_public(file_id: str, output_dir: Path) -> Optional[str]:
    """Tier 1: Try public download methods without authentication."""

    # Method 1: Direct API download
    url = f"https://www.googleapis.com/drive/v3/files/{file_id}?alt=media"
    try:
        content, headers = make_request(url)
        if 'status' not in headers:  # Success
            filename = headers.get('Content-Disposition', f'file_{file_id}')
            if 'filename=' in filename:
                filename = filename.split('filename=')[1].strip('"')
            else:
                filename = f"gdrive_{file_id}"

            filepath = output_dir / filename
            filepath.write_bytes(content)
            return str(filepath)
    except Exception:
        pass

    # Method 2: Direct download with confirmation
    url = f"https://drive.usercontent.google.com/download?id={file_id}&export=download&confirm=t"
    try:
        content, headers = make_request(url)
        if 'status' not in headers:
            # Extract filename from Content-Disposition or use default
            filename = f"gdrive_{file_id}"
            cd = headers.get('Content-Disposition', '')
            if 'filename=' in cd:
                # Parse filename from Content-Disposition header
                match = re.search(r'filename[^;=\n]*=(([\'"]).*?\2|[^;\n]*)', cd)
                if match:
                    filename = match.group(1).strip('\'"')

            filepath = output_dir / filename
            filepath.write_bytes(content)
            return str(filepath)
    except Exception:
        pass

    # Method 3: Googleusercontent (works for images)
    url = f"https://lh3.googleusercontent.com/d/{file_id}"
    try:
        content, headers = make_request(url)
        if 'status' not in headers and len(content) > 0:
            # Check if it's not an error page
            if not content.startswith(b'<!DOCTYPE') and not content.startswith(b'<html'):
                filename = f"gdrive_{file_id}.jpg"  # Default to jpg for images
                filepath = output_dir / filename
                filepath.write_bytes(content)
                return str(filepath)
    except Exception:
        pass

    return None


def get_sa_token() -> Optional[str]:
    """Tier 2: Generate JWT token from service account key."""
    if not SA_KEY_PATH.exists():
        return None

    try:
        import jwt
        from datetime import datetime, timedelta
    except ImportError:
        print("Warning: PyJWT not installed, skipping service account auth", file=sys.stderr)
        return None

    try:
        with open(SA_KEY_PATH) as f:
            sa_data = json.load(f)

        # Create JWT assertion
        now = datetime.utcnow()
        payload = {
            "iss": sa_data["client_email"],
            "scope": "https://www.googleapis.com/auth/drive.readonly",
            "aud": "https://oauth2.googleapis.com/token",
            "exp": int((now + timedelta(hours=1)).timestamp()),
            "iat": int(now.timestamp()),
        }

        # Sign with private key
        assertion = jwt.encode(payload, sa_data["private_key"], algorithm="RS256")

        # Exchange JWT for access token
        token_url = "https://oauth2.googleapis.com/token"
        data = urllib.parse.urlencode({
            "grant_type": "urn:ietf:params:oauth:grant-type:jwt-bearer",
            "assertion": assertion
        }).encode()

        response, headers = make_request(token_url, data=data)

        if 'status' in headers:
            print(f"SA token exchange failed: {headers.get('reason')}", file=sys.stderr)
            return None

        token_data = json.loads(response)
        return token_data.get("access_token")

    except Exception as e:
        print(f"SA token generation error: {e}", file=sys.stderr)
        return None


def parse_expiry(value) -> float:
    """Return an OAuth expiry as a Unix timestamp."""
    if isinstance(value, (int, float)):
        return float(value)
    if isinstance(value, str):
        try:
            return datetime.fromisoformat(value.replace("Z", "+00:00")).timestamp()
        except ValueError:
            return 0
    return 0


def get_oauth_token() -> Optional[str]:
    """Tier 2: Get or refresh the OAuth2 access token."""
    if not OAUTH_TOKEN_PATH.exists():
        return None

    try:
        with open(OAUTH_TOKEN_PATH) as f:
            token_data = json.load(f)

        refresh_token = token_data.get("refresh_token")
        if not refresh_token:
            return None

        # Try to use existing access token if not expired
        access_token = token_data.get("access_token")
        expiry = token_data.get("token_expiry")
        if access_token and expiry:
            # Check if token is still valid (with 5 min buffer)
            expiry_time = parse_expiry(expiry)
            if expiry_time > time.time() + 300:
                return access_token

        # Need to refresh
        client_id = token_data.get("client_id")
        client_secret = token_data.get("client_secret")

        if not (client_id and client_secret):
            print("OAuth token file missing client_id or client_secret", file=sys.stderr)
            return None

        token_url = "https://oauth2.googleapis.com/token"
        data = urllib.parse.urlencode({
            "client_id": client_id,
            "client_secret": client_secret,
            "refresh_token": refresh_token,
            "grant_type": "refresh_token"
        }).encode()

        response, headers = make_request(token_url, data=data)

        if 'status' in headers:
            print(f"OAuth refresh failed: {headers.get('reason')}", file=sys.stderr)
            print("Please set up service account authentication", file=sys.stderr)
            return None

        new_token_data = json.loads(response)
        access_token = new_token_data.get("access_token")
        if access_token:
            token_data["access_token"] = access_token
            token_data["token_expiry"] = datetime.fromtimestamp(
                time.time() + int(new_token_data.get("expires_in", 3600)), timezone.utc
            ).isoformat().replace("+00:00", "Z")
            if new_token_data.get("refresh_token"):
                token_data["refresh_token"] = new_token_data["refresh_token"]
            tmp_path = OAUTH_TOKEN_PATH.with_suffix(".json.tmp")
            tmp_path.write_text(json.dumps(token_data, indent=2) + "\n")
            os.chmod(tmp_path, 0o600)
            tmp_path.replace(OAUTH_TOKEN_PATH)
        return access_token

    except Exception as e:
        print(f"OAuth token error: {e}", file=sys.stderr)
        return None


def get_file_metadata(file_id: str, token: str) -> Optional[Dict]:
    """Get file metadata from Drive API."""
    url = f"https://www.googleapis.com/drive/v3/files/{file_id}?fields=name,mimeType,size"
    headers = {"Authorization": f"Bearer {token}"}

    try:
        response, resp_headers = make_request(url, headers=headers)
        if 'status' in resp_headers:
            return None
        return json.loads(response)
    except Exception:
        return None


def download_with_auth(file_id: str, token: str, output_dir: Path) -> Optional[str]:
    """Download file using authenticated token."""

    # Get file metadata first
    metadata = get_file_metadata(file_id, token)
    if not metadata:
        print("Failed to get file metadata", file=sys.stderr)
        return None

    filename = metadata.get("name", f"gdrive_{file_id}")
    mime_type = metadata.get("mimeType", "")

    # Check if it's a Google Workspace file that needs export
    if mime_type in EXPORT_FORMATS:
        export_mime, extension = EXPORT_FORMATS[mime_type]
        url = f"https://www.googleapis.com/drive/v3/files/{file_id}/export?mimeType={urllib.parse.quote(export_mime)}"
        # Update filename with correct extension
        if not filename.endswith(f".{extension}"):
            filename = f"{filename}.{extension}"
    else:
        url = f"https://www.googleapis.com/drive/v3/files/{file_id}?alt=media"

    headers = {"Authorization": f"Bearer {token}"}

    try:
        content, resp_headers = make_request(url, headers=headers)

        if 'status' in resp_headers:
            status = resp_headers.get('status')
            print(f"Download failed with status {status}: {resp_headers.get('reason')}", file=sys.stderr)
            if status == 404:
                print("File not found or not accessible with current credentials", file=sys.stderr)
            elif status == 403:
                print("Permission denied. File may not be shared with this account.", file=sys.stderr)
            return None

        # Save file
        filepath = output_dir / filename
        filepath.write_bytes(content)
        return str(filepath)

    except Exception as e:
        print(f"Download error: {e}", file=sys.stderr)
        return None


def list_folder_files(folder_id: str, token: Optional[str] = None) -> list:
    """List all files in a Google Drive folder.

    Uses pagination to handle large folders (100+ files).
    Returns list of dicts with 'id', 'name', 'mimeType', 'size'.
    """
    files = []
    page_token = None

    while True:
        url = (
            f"https://www.googleapis.com/drive/v3/files"
            f"?q=%27{folder_id}%27+in+parents"
            f"&fields=nextPageToken,files(id,name,mimeType,size)"
            f"&pageSize=100"
        )
        if page_token:
            url += f"&pageToken={page_token}"

        headers: Dict[str, str] = {}
        if token:
            headers["Authorization"] = f"Bearer {token}"

        try:
            response, resp_headers = make_request(url, headers=headers)
            if 'status' in resp_headers:
                print(
                    f"Folder listing failed: {resp_headers.get('status')} {resp_headers.get('reason')}",
                    file=sys.stderr,
                )
                break

            data = json.loads(response)
            files.extend(data.get('files', []))

            page_token = data.get('nextPageToken')
            if not page_token:
                break
        except Exception as e:
            print(f"Error listing folder: {e}", file=sys.stderr)
            break

    return files


def download_folder(folder_id: str, output_dir: Path) -> list:
    """Download all files from a Google Drive folder.

    Tries public access first, then service account, then OAuth.
    Skips subfolders (non-recursive).
    Returns list of downloaded file paths.
    """
    downloaded = []

    # Try to list files — first without auth (public folders)
    files = list_folder_files(folder_id)

    token = None
    if not files:
        # Try OAuth first, then the service account fallback.
        token = get_oauth_token()
        if token:
            print("Using OAuth2 for folder listing", file=sys.stderr)
            files = list_folder_files(folder_id, token)

    if not files:
        token = get_sa_token()
        if token:
            print("Using service account for folder listing", file=sys.stderr)
            files = list_folder_files(folder_id, token)

    if not files:
        print("No files found in folder or access denied", file=sys.stderr)
        return []

    print(f"Found {len(files)} files in folder", file=sys.stderr)

    # Create subfolder for this folder's contents
    folder_dir = output_dir / f"folder_{folder_id[:8]}"
    folder_dir.mkdir(parents=True, exist_ok=True)

    for i, file_info in enumerate(files, 1):
        file_id = file_info['id']
        file_name = file_info.get('name', f'file_{file_id}')
        mime_type = file_info.get('mimeType', '')

        # Skip subfolders (recursive download not supported)
        if mime_type == 'application/vnd.google-apps.folder':
            print(f"  [{i}/{len(files)}] Skipping subfolder: {file_name}", file=sys.stderr)
            continue

        print(f"  [{i}/{len(files)}] Downloading: {file_name}", file=sys.stderr)

        filepath = None

        if token:
            filepath = download_with_auth(file_id, token, folder_dir)

        if not filepath:
            filepath = download_public(file_id, folder_dir)

        if filepath:
            downloaded.append(filepath)
            print(f"  [{i}/{len(files)}] OK: {filepath}", file=sys.stderr)
        else:
            print(f"  [{i}/{len(files)}] FAILED: {file_name}", file=sys.stderr)

    return downloaded


def main():
    """Main entry point."""
    # Parse optional --output-dir
    args = sys.argv[1:]
    output_dir_override = None
    if '--output-dir' in args:
        idx = args.index('--output-dir')
        if idx + 1 < len(args):
            output_dir_override = Path(args[idx + 1])
            args = args[:idx] + args[idx+2:]

    if not args:
        print("Usage: gdrive-download.py [--output-dir DIR] <URL_or_FILE_ID>", file=sys.stderr)
        sys.exit(1)

    input_str = args[0]

    # Resolve short links / redirects to Google Drive URL
    # Only follow redirects if input is NOT already a Google Drive / googleapis URL
    # and NOT a raw file ID (25-50 alphanumeric chars)
    is_drive_url = "drive.google.com" in input_str or "googleapis.com" in input_str or "docs.google.com" in input_str
    is_raw_id = bool(re.match(r'^[\w-]{25,50}$', input_str))
    if not is_drive_url and not is_raw_id and input_str.startswith("http"):
        print(f"Resolving short link: {input_str}", file=sys.stderr)
        resolved = resolve_redirect(input_str)
        if resolved != input_str:
            print(f"Resolved to: {resolved}", file=sys.stderr)
            input_str = resolved

    # Determine if this is a file or folder
    item_id, item_type = extract_id_and_type(input_str)
    if not item_id:
        print(f"Invalid Google Drive URL or file ID: {input_str}", file=sys.stderr)
        sys.exit(1)

    # Determine output directory
    if output_dir_override:
        output_dir = output_dir_override
    else:
        output_dir = get_output_dir()
    output_dir.mkdir(parents=True, exist_ok=True)

    # Create marker file for cleanup script
    marker = output_dir / ".claude-marker"
    if not marker.exists():
        marker.write_text("claude-downloads directory - safe to clean files older than 24h\n")

    # Route: folder vs file
    if item_type == 'folder':
        print(f"Downloading folder: {item_id}", file=sys.stderr)
        downloaded = download_folder(item_id, output_dir)
        if downloaded:
            for path in downloaded:
                print(path)
            print(f"Downloaded {len(downloaded)} files", file=sys.stderr)
            sys.exit(0)
        else:
            print("Failed to download folder contents", file=sys.stderr)
            sys.exit(1)

    # Single file download (original 3-tier logic)
    file_id = item_id

    # Tier 1: Try public download
    print(f"Attempting public download for file ID: {file_id}", file=sys.stderr)
    filepath = download_public(file_id, output_dir)
    if filepath:
        print(filepath)  # Success - print to stdout
        sys.exit(0)

    print("Public download failed, trying authenticated methods...", file=sys.stderr)

    # Tier 2: Try OAuth refresh
    token = get_oauth_token()
    if token:
        print("Using OAuth2 authentication", file=sys.stderr)
        filepath = download_with_auth(file_id, token, output_dir)
        if filepath:
            print(filepath)
            sys.exit(0)
    else:
        print("OAuth2 not available", file=sys.stderr)

    # Tier 3: Try service account fallback
    token = get_sa_token()
    if token:
        print("Using service account authentication", file=sys.stderr)
        filepath = download_with_auth(file_id, token, output_dir)
        if filepath:
            print(filepath)
            sys.exit(0)
    else:
        print("Service account not available", file=sys.stderr)

    # All methods failed
    print("All download methods failed", file=sys.stderr)
    print("File may be private or require authentication setup", file=sys.stderr)
    print(f"To enable authenticated downloads, set up service account key at: {SA_KEY_PATH}", file=sys.stderr)
    sys.exit(1)


if __name__ == "__main__":
    main()
