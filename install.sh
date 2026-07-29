#!/usr/bin/env bash

if [ -z "${BASH_VERSION:-}" ]; then
	echo "Error: this script requires bash (not sh, dash, ash, or zsh)." >&2
	echo "Install bash and re-run:  bash install.sh" >&2
	exit 1
fi

set -euo pipefail
shopt -s inherit_errexit 2>/dev/null || true

SCRIPT_NAME="${0##*/}"
SCRIPT_VERSION="2.0.0"

SELF_HASH="3c36b5c9357829a358c8d365bb2b604435cd22665d72b9868e028fa48c6ed3f7"
if [ -f "$0" ] && [ "$0" != "bash" ] && [ "${0##*/}" != "bash" ] && [ -r "$0" ]; then
	if command -v sha256sum >/dev/null 2>&1 && command -v sed >/dev/null 2>&1; then
		computed=$(sed '/^SELF_HASH=/d' "$0" 2>/dev/null | sha256sum | cut -d' ' -f1)
		if [ -n "$computed" ] && [ "$SELF_HASH" != "3c36b5c9357829a358c8d365bb2b604435cd22665d72b9868e028fa48c6ed3f7" ] && [ "$computed" != "$SELF_HASH" ]; then
			printf '\033[1;33m[!]\033[0m WARNING: script integrity check failed!\n' >&2
			printf '   Expected: %s\n' "$SELF_HASH" >&2
			printf '   Got:      %s\n' "$computed" >&2
			printf '   Continue anyway? [y/N] ' >&2
			read -r answer
			case "$answer" in [yY]|[yY][eE][sS]) ;; *) exit 1 ;; esac
		fi
	fi
fi

DOWNLOAD_PAGE="https://antigravity.google/download"
CLI_INSTALL_URL="https://antigravity.google/cli/install.sh"
CLI_MANIFEST_BASE="https://antigravity-cli-auto-updater-974169037036.us-central1.run.app/manifests"
SDK_PACKAGE="antigravity-sdk"

DRY_RUN=0
FORCE=0
QUIET=0
VERBOSE=0
USER_MODE=0
PIPE_MODE=0
KEEP_PREVIOUS=1
MODE="install"
SELECTED_PRODUCTS=()
PRODUCTS_JSON=""
PLATFORM=""
OPT_PREFIX=""
BIN_PREFIX=""
DATA_PREFIX=""

PKG_MGR=""
PKG_INSTALL=""

TMPDIR=""
STAGING_DIR=""

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

cleanup() {
	local rv=$?
	if [ -n "${TMPDIR:-}" ] && [ -d "$TMPDIR" ]; then
		rm -rf "$TMPDIR" 2>/dev/null || true
	fi
	if [ -n "${STAGING_DIR:-}" ] && [ -d "$STAGING_DIR" ]; then
		rm -rf "$STAGING_DIR" 2>/dev/null || true
	fi
	exit $rv
}
trap cleanup EXIT INT TERM

log_info()  { [ "$QUIET" -eq 0 ] && printf "${BLUE}[*]${NC} %s\n" "$*" >&2; return 0; }
log_ok()    { [ "$QUIET" -eq 0 ] && printf "${GREEN}[+]${NC} %s\n" "$*" >&2; return 0; }
log_warn()  { printf "${YELLOW}[!]${NC} %s\n" "$*" >&2; }
log_error() { printf "${RED}[x]${NC} %s\n" "$*" >&2; }
log_verbose() { [ "$VERBOSE" -eq 1 ] && printf "${CYAN}[v]${NC} %s\n" "$*" >&2; return 0; }
log_dryrun() { printf "${YELLOW}[DRY-RUN]${NC} %s\n" "$*" >&2; }

detect_platform() {
	case "$(uname -m)" in
		x86_64 | amd64) PLATFORM="linux-x64" ;;
		aarch64 | arm64) PLATFORM="linux-arm" ;;
		*)
			log_error "Unsupported architecture: $(uname -m)"
			exit 1
			;;
	esac
	log_verbose "Platform: $PLATFORM"
}

define_product_config() {
	local product_id="$1"
	case "$product_id" in
		antigravity)
			PRODUCT_NAME="Antigravity 2.0"
			PRODUCT_INSTALL_ROOT="$OPT_PREFIX/antigravity-hub"
			PRODUCT_ARCHIVE_DIR="Antigravity"
			PRODUCT_BINARY_NAME="antigravity"
			PRODUCT_DESKTOP_FILE="$DATA_PREFIX/applications/antigravity.desktop"
			PRODUCT_ICON_FILE="$DATA_PREFIX/icons/hicolor/512x512/apps/antigravity.png"
			PRODUCT_ICON_SOURCE="resources/app/resources/linux/code.png"
			PRODUCT_COMMAND_LINK="$BIN_PREFIX/antigravity"
			PRODUCT_WM_CLASS="antigravity"
			PRODUCT_URL_PATTERN="antigravity-hub"
			PRODUCT_HAS_SANDBOX=0
			;;
		ide)
			PRODUCT_NAME="Antigravity IDE"
			PRODUCT_INSTALL_ROOT="$OPT_PREFIX/antigravity-ide"
			PRODUCT_ARCHIVE_DIR="Antigravity IDE"
			PRODUCT_INSTALL_DIR="Antigravity-IDE"
			PRODUCT_BINARY_NAME="antigravity-ide"
			PRODUCT_DESKTOP_FILE="$DATA_PREFIX/applications/antigravity-ide.desktop"
			PRODUCT_ICON_FILE="$DATA_PREFIX/icons/hicolor/512x512/apps/antigravity-ide.png"
			PRODUCT_ICON_SOURCE="resources/app/resources/linux/code.png"
			PRODUCT_COMMAND_LINK="$BIN_PREFIX/antigravity-ide"
			PRODUCT_WM_CLASS="antigravity-ide"
			PRODUCT_URL_PATTERN="/antigravity/stable/"
			PRODUCT_HAS_SANDBOX=1
			PRODUCT_SANDBOX_PATH="chrome-sandbox"
			PRODUCT_VERSION_FILE=".linuxcapable-version"
			;;
		sdk)
			PRODUCT_NAME="Antigravity SDK"
			PRODUCT_INSTALL_ROOT=""
			PRODUCT_ARCHIVE_DIR=""
			PRODUCT_BINARY_NAME=""
			PRODUCT_DESKTOP_FILE=""
			PRODUCT_ICON_FILE=""
			PRODUCT_COMMAND_LINK=""
			PRODUCT_WM_CLASS=""
			PRODUCT_URL_PATTERN=""
			PRODUCT_HAS_SANDBOX=0
			;;
		cli)
			PRODUCT_NAME="Antigravity CLI"
			PRODUCT_INSTALL_ROOT=""
			PRODUCT_ARCHIVE_DIR=""
			PRODUCT_BINARY_NAME="agy"
			PRODUCT_DESKTOP_FILE=""
			PRODUCT_ICON_FILE=""
			PRODUCT_COMMAND_LINK=""
			PRODUCT_WM_CLASS=""
			PRODUCT_URL_PATTERN=""
			PRODUCT_HAS_SANDBOX=0
			PRODUCT_CLI_BINARY_PATH="$BIN_PREFIX/agy"
			;;
		*)
			log_error "Unknown product: $product_id"
			return 1
			;;
	esac
}

extract_all_products() {
	log_verbose "Extracting product info from download page..."

	local html_file="$TMPDIR/download.html"
	download_with_retry "$html_file" "$DOWNLOAD_PAGE"

	local extracted
	if ! extracted=$(python3 - "$html_file" "$PLATFORM" <<'PYEOF'
import json
import re
import sys
from pathlib import Path
from urllib.parse import urljoin

html = Path(sys.argv[1]).read_text(errors="replace")
platform = sys.argv[2]
page_url = "https://antigravity.google/download"

products = {
	"antigravity": {"version": None, "build": None, "url": None},
	"ide": {"version": None, "build": None, "url": None},
	"cli": {"version": None, "url": None},
	"sdk": {"version": None, "url": None},
}

tar_urls = re.findall(r'href="(https://[^"]*\.tar\.gz)"', html)
for url in tar_urls:
	url_plat = "linux-arm" if "/linux-arm/" in url else "linux-x64"
	if url_plat != platform:
		continue

	vm = re.search(r'/([\d]+\.[\d]+\.[\d]+(?:-[^/]+)?)/' + re.escape(url_plat), url)
	ver = vm.group(1) if vm else None
	if not ver:
		continue

	if "antigravity-hub" in url:
		parts = ver.split("-", 1)
		products["antigravity"]["version"] = parts[0]
		products["antigravity"]["build"] = parts[1] if len(parts) > 1 else ""
		products["antigravity"]["url"] = url
	elif "/antigravity/stable/" in url and "IDE" in url:
		parts = ver.split("-", 1)
		products["ide"]["version"] = parts[0]
		products["ide"]["build"] = parts[1] if len(parts) > 1 else ""
		products["ide"]["url"] = url

if not products["antigravity"]["url"] or not products["ide"]["url"]:
	matches = re.findall(r'(?:src|href)="([^"]*main-[^"]+\.js)"', html)
	if matches:
		js_url = urljoin(page_url, matches[-1])
		js_content = None
		import urllib.request
		try:
			with urllib.request.urlopen(js_url) as resp:
				js_content = resp.read().decode("utf-8", errors="replace")
		except Exception:
			pass

		if js_content:
			for prod_id, js_prod_id in [("antigravity", "antigravity"), ("ide", "antigravity-ide")]:
				if products[prod_id]["url"]:
					continue
				start = js_content.find(f'id:"{js_prod_id}"')
				end_marker = f'id:"antigravity-'
				end_candidates = []
				for marker_id in ["antigravity-sdk", "antigravity-cli"]:
					e = js_content.find(f'id:"{marker_id}"', start)
					if e != -1:
						end_candidates.append(e)
				end = min(end_candidates) if end_candidates else -1
				if start == -1 or end == -1:
					continue
				section = js_content[start:end]
				plat_rel_js = "linux-arm" if platform == "linux-arm" else "linux-x64"
				if prod_id == "ide":
					url_match = re.search(r'href:"([^"]+/' + re.escape(plat_rel_js) + r'/Antigravity%20IDE\.tar\.gz)"', section)
				else:
					url_match = re.search(r'href:"([^"]+/' + re.escape(plat_rel_js) + r'/Antigravity\.tar\.gz)"', section)
				if url_match:
					products[prod_id]["url"] = url_match.group(1)
					vm = re.search(r'/stable/([^/]+)/', url_match.group(1))
					if vm:
						parts = vm.group(1).split("-", 1)
						products[prod_id]["version"] = parts[0]
						products[prod_id]["build"] = parts[1] if len(parts) > 1 else ""

plain = re.sub(r'<[^>]+>', ' ', html)
plain = re.sub(r'\s+', ' ', plain)

cli_match = re.search(r'Antigravity\s+CLI\s+v?(\d+\.\d+\.\d+)', plain)
if cli_match:
	products["cli"]["version"] = cli_match.group(1)

sdk_match = re.search(r'Antigravity\s+SDK\s+v?(\d+\.\d+\.\d+)', plain)
if sdk_match:
	products["sdk"]["version"] = sdk_match.group(1)

gh_match = re.search(r'https://github\.com/google-antigravity/antigravity-sdk-python', html)
if gh_match:
	products["sdk"]["url"] = gh_match.group(0)

print(json.dumps(products))
PYEOF
	); then
		log_error "Failed to extract product information from download page"
		exit 1
	fi

	PRODUCTS_JSON="$extracted"
	log_verbose "Raw product data: $PRODUCTS_JSON"
}

get_remote_version() {
	local product_id="$1"
	local version
	version=$(echo "$PRODUCTS_JSON" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('$product_id',{}).get('version','') or '')" 2>/dev/null || echo "")
	echo "$version"
}

get_remote_url() {
	local product_id="$1"
	local url
	url=$(echo "$PRODUCTS_JSON" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('$product_id',{}).get('url','') or '')" 2>/dev/null || echo "")
	echo "$url"
}

get_remote_build() {
	local product_id="$1"
	local build
	build=$(echo "$PRODUCTS_JSON" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('$product_id',{}).get('build','') or '')" 2>/dev/null || echo "")
	echo "$build"
}

read_manifest() {
	local manifest_file
	if [ "$USER_MODE" -eq 1 ]; then
		manifest_file="$HOME/.local/share/antigravity/.products.json"
	else
		manifest_file="/opt/antigravity/.products.json"
	fi
	if [ -f "$manifest_file" ]; then
		cat "$manifest_file"
	else
		echo '{"products":{}}'
	fi
}

write_manifest() {
	local manifest_json="$1"
	local manifest_file
	if [ "$USER_MODE" -eq 1 ]; then
		manifest_file="$HOME/.local/share/antigravity/.products.json"
	else
		manifest_file="/opt/antigravity/.products.json"
	fi
	if [ "$DRY_RUN" -eq 1 ]; then
		log_dryrun "Would write manifest to $manifest_file"
		return 0
	fi
	mkdir -p "$(dirname "$manifest_file")"
	echo "$manifest_json" > "$manifest_file"
}

get_installed_version() {
	local product_id="$1"
	local manifest
	manifest=$(read_manifest)
	echo "$manifest" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('products',{}).get('$product_id',{}).get('version','') or '')" 2>/dev/null || echo ""
}

detect_distro() {
	if command -v apt >/dev/null 2>&1; then
		PKG_MGR="apt"
		PKG_INSTALL="apt-get install -y -qq"
		PKG_CURL="curl"
		PKG_TAR="tar"
		PKG_PYTHON="python3"
		PKG_PIP="python3-pip"
		PKG_PIPX="pipx"
	elif command -v dnf >/dev/null 2>&1; then
		PKG_MGR="dnf"
		PKG_INSTALL="dnf install -y -q"
		PKG_CURL="curl"
		PKG_TAR="tar"
		PKG_PYTHON="python3"
		PKG_PIP="python3-pip"
		PKG_PIPX="pipx"
	elif command -v pacman >/dev/null 2>&1; then
		PKG_MGR="pacman"
		PKG_INSTALL="pacman -S --noconfirm --noprogressbar"
		PKG_CURL="curl"
		PKG_TAR="tar"
		PKG_PYTHON="python"
		PKG_PIP="python-pip"
		PKG_PIPX="python-pipx"
	elif command -v zypper >/dev/null 2>&1; then
		PKG_MGR="zypper"
		PKG_INSTALL="zypper install -y --no-recommends"
		PKG_CURL="curl"
		PKG_TAR="tar"
		PKG_PYTHON="python3"
		PKG_PIP="python3-pip"
		PKG_PIPX="pipx"
	elif command -v apk >/dev/null 2>&1; then
		PKG_MGR="apk"
		PKG_INSTALL="apk add --no-cache"
		PKG_CURL="curl"
		PKG_TAR="tar"
		PKG_PYTHON="python3"
		PKG_PIP="py3-pip"
		PKG_PIPX="pipx"
	fi
	log_verbose "Package manager: ${PKG_MGR:-none detected}"
}

check_glibc() {
	if command -v ldd >/dev/null 2>&1; then
		local ldd_out
		ldd_out=$(ldd --version 2>&1 | head -1) || true
		if echo "$ldd_out" | grep -qi musl; then
			log_error "Musl libc detected. Prebuilt Antigravity binaries require glibc."
			log_error "Alpine Linux is not supported for desktop products (Antigravity 2.0, IDE)."
			log_error "Try: apk add gcompat"
			log_error "CLI and SDK can still be installed on musl systems."
			return 1
		fi
		local ver
		ver=$(echo "$ldd_out" | grep -oP '\d+\.\d+' | head -1) || true
		local min_glibc="2.28"
		if [ -n "$ver" ]; then
			if printf '%s\n%s\n' "$min_glibc" "$ver" | sort -V -C 2>/dev/null; then
				: # ver >= min_glibc
			else
				if [ "$(printf '%s\n' "$min_glibc" "$ver" | sort -V | head -1)" != "$min_glibc" ]; then
					log_error "glibc $ver is too old. Minimum required: glibc $min_glibc"
					log_error "Supported: Debian 10+, Ubuntu 20.04+, RHEL 8+, Fedora 36+"
					return 1
				fi
			fi
		fi
	fi
	log_verbose "glibc check passed"
	return 0
}

check_deps() {
	local missing=()
	for cmd in curl tar python3; do
		if ! command -v "$cmd" >/dev/null 2>&1; then
			missing+=("$cmd")
		fi
	done
	if [ ${#missing[@]} -eq 0 ]; then
		return 0
	fi

	if [ -z "$PKG_MGR" ]; then
		log_error "Missing required commands: ${missing[*]}"
		log_error "Install them with your system package manager and re-run."
		exit 1
	fi

	local can_install=0
	if [ "$(id -u)" -eq 0 ]; then
		can_install=1
	elif command -v sudo >/dev/null 2>&1 && sudo -n true 2>/dev/null; then
		can_install=1
	fi

	if [ "$can_install" -eq 0 ] || [ "$PIPE_MODE" -eq 1 ]; then
		log_error "Missing required commands: ${missing[*]}"
		log_error "Install with: sudo $PKG_INSTALL ${missing[*]}"
		exit 1
	fi

	log_info "Installing missing dependencies: ${missing[*]}"
	local pkgs_to_install=""
	for cmd in "${missing[@]}"; do
		case "$cmd" in
			curl)    pkgs_to_install="$pkgs_to_install $PKG_CURL" ;;
			tar)     pkgs_to_install="$pkgs_to_install $PKG_TAR" ;;
			python3) pkgs_to_install="$pkgs_to_install $PKG_PYTHON" ;;
		esac
	done

	if [ "$(id -u)" -eq 0 ]; then
		$PKG_INSTALL $pkgs_to_install || {
			log_error "Failed to install dependencies. Install manually and re-run."
			exit 1
		}
	else
		sudo $PKG_INSTALL $pkgs_to_install || {
			log_error "Failed to install dependencies. Install manually and re-run."
			exit 1
		}
	fi
	log_ok "Dependencies installed"
}

check_root() {
	if [ "$USER_MODE" -eq 1 ]; then
		return 0
	fi
	if [ "$(id -u)" -ne 0 ]; then
		log_error "Requires root. Use: sudo $SCRIPT_NAME"
		log_error "Or use: $SCRIPT_NAME --user"
		exit 1
	fi
}

download_with_retry() {
	local output="$1"
	local url="$2"
	local max_retries=3
	local attempt=1
	local wait_time=1

	while [ $attempt -le $max_retries ]; do
		log_verbose "Downloading $url (attempt $attempt/$max_retries)..."
		if curl -fsSL --compressed --connect-timeout 15 --max-time 300 \
			-o "$output" "$url" 2>/dev/null; then
			return 0
		fi
		log_verbose "Download failed, waiting ${wait_time}s before retry..."
		sleep "$wait_time"
		wait_time=$((wait_time * 3))
		attempt=$((attempt + 1))
	done
	log_error "Failed to download $url after $max_retries attempts"
	return 1
}

check_sandbox_perms() {
	local sandbox_path="$1"
	if [ ! -f "$sandbox_path" ]; then
		return 1
	fi
	local perms
	perms=$(stat -c '%U:%G:%a' "$sandbox_path" 2>/dev/null || echo "")
	if [ "$USER_MODE" -eq 1 ]; then
		[ "$perms" = "$(whoami):$(id -gn):4755" ] || [ "$perms" = "$(whoami):$(id -gn):755" ]
	else
		[ "$perms" = "root:root:4755" ]
	fi
}

check_disk_space() {
	local required_mb="${1:-500}"
	local check_dir="${2:-/opt}"
	while [ ! -d "$check_dir" ] && [ "$check_dir" != "/" ]; do
		check_dir=$(dirname "$check_dir")
	done
	local available
	available=$(df -m "$check_dir" 2>/dev/null | awk 'NR==2 {print $4}' || echo "0")
	if [ "$available" -lt "$required_mb" ]; then
		log_error "Insufficient disk space in $check_dir: ${available}MB available, ${required_mb}MB required"
		return 1
	fi
	log_verbose "Disk space OK: ${available}MB available in $check_dir"
}

ensure_tmpdir() {
	if [ -z "${TMPDIR:-}" ]; then
		local tmp_parent="${TMPDIR:-/tmp}"
		TMPDIR=$(mktemp -d "$tmp_parent/antigravity.XXXXXX")
	fi
}

show_help() {
	cat <<HELP
$SCRIPT_NAME v$SCRIPT_VERSION - Google Antigravity Product Installer

Usage: $SCRIPT_NAME [OPTIONS] [PRODUCTS...]

Products: antigravity, ide, cli, sdk, all

Run without arguments for an interactive selection menu.

Options:
  --install PRODUCT   Install specific product (can be repeated)
  --update            Update all installed products
  --uninstall PRODUCT Uninstall a product
  --list              List installed vs available versions
  --dry-run           Preview actions without executing them
  --force             Force reinstall even if already up to date
  --user              Install for current user only (no root required)
  --keep-previous N   Keep N previous backup versions (default: 1)
  --verbose           Detailed output for debugging
  --quiet             Minimal output
  --help              Show this help

Examples:
  $SCRIPT_NAME                        Interactive menu
  $SCRIPT_NAME --install ide          Install Antigravity IDE
  $SCRIPT_NAME --user --install cli   Install CLI for current user only
  $SCRIPT_NAME --list                 Show all products and versions
  $SCRIPT_NAME --dry-run --force ide  Preview IDE reinstall
  $SCRIPT_NAME --uninstall ide cli    Remove IDE and CLI
HELP
	exit 0
}

is_valid_product() {
	case "$1" in
		antigravity|ide|cli|sdk|all) return 0 ;;
		*) return 1 ;;
	esac
}

parse_args() {
	local positional=()

	while [ $# -gt 0 ]; do
		case "$1" in
			--dry-run)
				DRY_RUN=1
				shift
				;;
			--force)
				FORCE=1
				shift
				;;
			--quiet)
				QUIET=1
				shift
				;;
			--verbose)
				VERBOSE=1
				shift
				;;
			--user)
				USER_MODE=1
				shift
				;;
			--keep-previous)
				KEEP_PREVIOUS="${2:-1}"
				if ! [[ "$KEEP_PREVIOUS" =~ ^[0-9]+$ ]]; then
					log_error "--keep-previous requires a number"
					exit 1
				fi
				shift 2
				;;
			--install)
				MODE="install"
				if [ -z "${2:-}" ] || ! is_valid_product "${2}"; then
					log_error "--install requires a valid product: antigravity, ide, cli, sdk, all"
					exit 1
				fi
				if [ "${2}" = "all" ]; then
					SELECTED_PRODUCTS=("antigravity" "ide" "cli" "sdk")
				else
					SELECTED_PRODUCTS+=("$2")
				fi
				shift 2
				;;
			--update)
				MODE="update"
				shift
				;;
			--uninstall)
				MODE="uninstall"
				if [ -z "${2:-}" ] || ! is_valid_product "${2}"; then
					log_error "--uninstall requires a valid product: antigravity, ide, cli, sdk, all"
					exit 1
				fi
				if [ "${2}" = "all" ]; then
					SELECTED_PRODUCTS=("antigravity" "ide" "cli" "sdk")
				else
					SELECTED_PRODUCTS+=("$2")
				fi
				shift 2
				;;
			--list)
				MODE="list"
				shift
				;;
			--help|-h)
				show_help
				;;
			--version|-V)
				echo "$SCRIPT_NAME v$SCRIPT_VERSION"
				exit 0
				;;
			-*)
				log_error "Unknown option: $1"
				show_help
				;;
			*)
				case "$1" in
					antigravity|ide|cli|sdk)
						SELECTED_PRODUCTS+=("$1")
						;;
					all)
						SELECTED_PRODUCTS=("antigravity" "ide" "cli" "sdk")
						;;
					*)
						log_error "Unknown product: $1"
						log_error "Valid products: antigravity, ide, cli, sdk, all"
						exit 1
						;;
				esac
				shift
				;;
		esac
	done

	if [ "$MODE" = "update" ] && [ ${#SELECTED_PRODUCTS[@]} -eq 0 ]; then
		local manifest
		manifest=$(read_manifest)
		local installed
		installed=$(echo "$manifest" | python3 -c "
import json, sys
d = json.load(sys.stdin)
ids = [k for k in d.get('products', {}) if d['products'][k].get('version')]
print(' '.join(ids))
" 2>/dev/null || echo "")

		for pid in $installed; do
			SELECTED_PRODUCTS+=("$pid")
		done
		if [ ${#SELECTED_PRODUCTS[@]} -eq 0 ]; then
			log_warn "No products installed. Use --install to install products."
			exit 0
		fi
		log_info "Updating installed products: ${SELECTED_PRODUCTS[*]}"
	fi

	export DRY_RUN FORCE QUIET VERBOSE USER_MODE KEEP_PREVIOUS MODE
	export -p SELECTED_PRODUCTS 2>/dev/null || true
}

interactive_menu() {
	local available_products=("antigravity" "ide" "cli" "sdk")
	local labels=()
	local statuses=()
	local i

	echo ""
	echo -e "${BOLD}Google Antigravity - Product Installer${NC}"
	echo "========================================"
	echo ""

	for i in "${!available_products[@]}"; do
		local pid="${available_products[$i]}"
		define_product_config "$pid"
		local remote_ver installed_ver label status
		remote_ver=$(get_remote_version "$pid")
		installed_ver=$(get_installed_version "$pid")

		if [ -n "$installed_ver" ]; then
			if [ "$installed_ver" = "$remote_ver" ]; then
				status="${GREEN}up to date${NC}"
			else
				status="${YELLOW}update available${NC}"
			fi
			label=" $((i + 1)). $PRODUCT_NAME  (v${remote_ver})  [installed: v${installed_ver} - $status]"
		else
			status="not installed"
			label=" $((i + 1)). $PRODUCT_NAME  (v${remote_ver})  [not installed]"
		fi
		printf "%b\n" "$label"
	done

	echo " a. All products"
	echo " u. Update all installed"
	echo " q. Quit"
	echo ""

	while true; do
		printf "Select [1-4, a, u, q]: "
		read -r choice </dev/tty

		case "$choice" in
			1) SELECTED_PRODUCTS=("antigravity"); return 0 ;;
			2) SELECTED_PRODUCTS=("ide"); return 0 ;;
			3) SELECTED_PRODUCTS=("cli"); return 0 ;;
			4) SELECTED_PRODUCTS=("sdk"); return 0 ;;
			a|A) SELECTED_PRODUCTS=("antigravity" "ide" "cli" "sdk"); return 0 ;;
			u|U) MODE="update"; return 0 ;;
			q|Q) echo "Bye."; exit 0 ;;
			*) echo -e "${RED}Invalid choice. Try again.${NC}" ;;
		esac
	done
}

check_product() {
	local product_id="$1"
	define_product_config "$product_id"

	local installed_ver remote_ver
	installed_ver=$(get_installed_version "$product_id")
	remote_ver=$(get_remote_version "$product_id")

	if [ "$FORCE" -eq 1 ]; then
		log_verbose "Force mode: will reinstall $PRODUCT_NAME"
		return 1
	fi

	if [ -z "$installed_ver" ]; then
		log_verbose "$PRODUCT_NAME is not installed"
		return 1
	fi

	if [ "$installed_ver" = "$remote_ver" ]; then
		case "$product_id" in
			antigravity|ide)
				if [ -x "$PRODUCT_INSTALL_ROOT/${PRODUCT_INSTALL_DIR:-$PRODUCT_ARCHIVE_DIR}/$PRODUCT_BINARY_NAME" ] \
					&& [ -L "$PRODUCT_COMMAND_LINK" ] \
					&& [ "$(readlink -f "$PRODUCT_COMMAND_LINK" 2>/dev/null)" = "$PRODUCT_INSTALL_ROOT/${PRODUCT_INSTALL_DIR:-$PRODUCT_ARCHIVE_DIR}/$PRODUCT_BINARY_NAME" ] \
					&& [ -f "$PRODUCT_DESKTOP_FILE" ] \
					&& [ -f "$PRODUCT_ICON_FILE" ]; then
					if [ "$PRODUCT_HAS_SANDBOX" -eq 1 ]; then
						if check_sandbox_perms "$PRODUCT_INSTALL_ROOT/$PRODUCT_INSTALL_DIR/$PRODUCT_SANDBOX_PATH"; then
							log_ok "$PRODUCT_NAME v$installed_ver is already installed and up to date"
							return 0
						fi
					else
						log_ok "$PRODUCT_NAME v$installed_ver is already installed and up to date"
						return 0
					fi
				fi
				;;
			cli)
				if [ -x "$PRODUCT_CLI_BINARY_PATH" ]; then
					log_ok "$PRODUCT_NAME v$installed_ver is already installed at $PRODUCT_CLI_BINARY_PATH"
					return 0
				fi
				;;
			sdk)
				if pip show "$SDK_PACKAGE" >/dev/null 2>&1 || pipx runpip "$SDK_PACKAGE" show "$SDK_PACKAGE" >/dev/null 2>&1; then
					log_ok "$PRODUCT_NAME v$installed_ver is already installed"
					return 0
				fi
				;;
		esac
		log_warn "$PRODUCT_NAME version matches but installation appears broken. Reinstalling."
		return 1
	fi

	log_verbose "$PRODUCT_NAME: installed=$installed_ver, remote=$remote_ver"
	return 1
}

atomic_staging_install() {
	local product_id="$1"
	local extract_dir="$2"
	local staging_work="$3"

	define_product_config "$product_id"

	local install_base="$PRODUCT_INSTALL_ROOT"
	local install_dir_name="${PRODUCT_INSTALL_DIR:-$PRODUCT_ARCHIVE_DIR}"

	if [ "$DRY_RUN" -eq 1 ]; then
		log_dryrun "Would install $PRODUCT_NAME to $install_base/$install_dir_name"
		return 0
	fi

	local staging_root
	local parent_dir
	parent_dir=$(dirname "$install_base")
	mkdir -p "$parent_dir"
	staging_root=$(mktemp -d "$parent_dir/.antigravity-install.XXXXXX")
	chmod 0755 "$staging_root"

	cp -a "$extract_dir/$PRODUCT_ARCHIVE_DIR" "$staging_root/$install_dir_name"

	local version remote_ver
	remote_ver=$(get_remote_version "$product_id")
	version="${remote_ver:-unknown}"

	local version_file_name="${PRODUCT_VERSION_FILE:-.version}"
	printf '%s\n' "$version" > "$staging_root/$version_file_name"

	if [ "$PRODUCT_HAS_SANDBOX" -eq 1 ] && [ -f "$staging_root/$install_dir_name/$PRODUCT_SANDBOX_PATH" ]; then
		if [ "$USER_MODE" -eq 0 ]; then
			chown root:root "$staging_root/$install_dir_name/$PRODUCT_SANDBOX_PATH" 2>/dev/null || true
		fi
		chmod 4755 "$staging_root/$install_dir_name/$PRODUCT_SANDBOX_PATH" 2>/dev/null || true
	fi

	if [ -d "$install_base" ]; then
		rotate_backups "$install_base"
	fi

	mv "$staging_root" "$install_base"
	log_verbose "Installed to $install_base"

	if [ "$USER_MODE" -eq 0 ] && [ -n "$PRODUCT_COMMAND_LINK" ]; then
		mkdir -p "$(dirname "$PRODUCT_COMMAND_LINK")"
		ln -sfn "$install_base/$install_dir_name/$PRODUCT_BINARY_NAME" "$PRODUCT_COMMAND_LINK"
	fi
}

rotate_backups() {
	local target="$1"
	local max_backups="$KEEP_PREVIOUS"

	if [ "$max_backups" -eq 0 ]; then
		log_verbose "Removing $target (no backups kept)"
		rm -rf "$target"
		return
	fi

	local i=$max_backups
	while [ "$i" -gt 0 ]; do
		local prev_idx=$((i - 1))
		local old_suffix
		if [ "$prev_idx" -eq 0 ]; then
			old_suffix=".previous"
		else
			old_suffix=".previous.$prev_idx"
		fi
		local new_suffix=".previous.$i"

		if [ -d "${target}${old_suffix}" ]; then
			if [ "$i" -eq "$max_backups" ]; then
				rm -rf "${target}${old_suffix}"
			else
				mv "${target}${old_suffix}" "${target}${new_suffix}"
			fi
		fi
		i=$((i - 1))
	done

	mv "$target" "${target}.previous"
}

update_manifest_entry() {
	local product_id="$1"
	local remote_ver="$2"
	local current_manifest
	current_manifest=$(read_manifest)

	local new_manifest
	new_manifest=$(echo "$current_manifest" | python3 -c "
import json, sys, datetime
d = json.load(sys.stdin)
if 'products' not in d:
	d['products'] = {}
d['products']['$product_id'] = {
	'version': '$remote_ver',
	'installed_at': datetime.datetime.now(datetime.timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ')
}
print(json.dumps(d))
")

	write_manifest "$new_manifest"
}

remove_manifest_entry() {
	local product_id="$1"
	local current_manifest
	current_manifest=$(read_manifest)

	local new_manifest
	new_manifest=$(echo "$current_manifest" | python3 -c "
import json, sys
d = json.load(sys.stdin)
d.get('products', {}).pop('$product_id', None)
print(json.dumps(d))
")

	write_manifest "$new_manifest"
}

install_antigravity() {
	local product_id="antigravity"
	define_product_config "$product_id"

	if check_product "$product_id"; then
		return 0
	fi

	local remote_ver remote_url
	remote_ver=$(get_remote_version "$product_id")
	remote_url=$(get_remote_url "$product_id")

	if [ -z "$remote_url" ]; then
		log_error "Could not find download URL for $PRODUCT_NAME"
		return 1
	fi

	if ! check_disk_space 600 "$(dirname "$PRODUCT_INSTALL_ROOT")"; then
		return 1
	fi

	log_info "Installing $PRODUCT_NAME v$remote_ver..."
	log_verbose "Download URL: $remote_url"

	if [ "$DRY_RUN" -eq 1 ]; then
		log_dryrun "Would download and install $PRODUCT_NAME v$remote_ver"
		update_manifest_entry "$product_id" "$remote_ver"
		return 0
	fi

	ensure_tmpdir
	local archive="$TMPDIR/antigravity.tar.gz"
	download_with_retry "$archive" "$remote_url" || return 1

	local extract_dir="$TMPDIR/extract"
	mkdir -p "$extract_dir"
	tar -xzf "$archive" -C "$extract_dir"

	if [ ! -d "$extract_dir/$PRODUCT_ARCHIVE_DIR" ]; then
		log_error "Unexpected archive structure: expected '$PRODUCT_ARCHIVE_DIR'"
		return 1
	fi

	if [ ! -x "$extract_dir/$PRODUCT_ARCHIVE_DIR/$PRODUCT_BINARY_NAME" ]; then
		log_error "$PRODUCT_BINARY_NAME not found or not executable in archive"
		return 1
	fi

	local icon_source="$extract_dir/$PRODUCT_ARCHIVE_DIR/$PRODUCT_ICON_SOURCE"
	if [ -f "$icon_source" ]; then
		mkdir -p "$(dirname "$PRODUCT_ICON_FILE")"
		install -m 0644 "$icon_source" "$PRODUCT_ICON_FILE"
		log_verbose "Icon installed to $PRODUCT_ICON_FILE"
	fi

	atomic_staging_install "$product_id" "$extract_dir" ""

	if [ -f "$PRODUCT_DESKTOP_FILE" ] || [ "$DRY_RUN" -eq 0 ]; then
		mkdir -p "$(dirname "$PRODUCT_DESKTOP_FILE")"
		local desktop_icon_name="${PRODUCT_ICON_FILE##*/}"
		desktop_icon_name="${desktop_icon_name%.png}"
		local desktop_exec="$PRODUCT_COMMAND_LINK"

		cat > "$PRODUCT_DESKTOP_FILE" <<DESKTOP
[Desktop Entry]
Name=$PRODUCT_NAME
Comment=Google $PRODUCT_NAME
Exec=$desktop_exec %U
Icon=$desktop_icon_name
Terminal=false
Type=Application
Categories=Development;IDE;
MimeType=x-scheme-handler/antigravity;application/x-antigravity-workspace;
StartupNotify=true
StartupWMClass=$PRODUCT_WM_CLASS
DESKTOP
		log_verbose "Desktop entry written to $PRODUCT_DESKTOP_FILE"
	fi

	update_manifest_entry "$product_id" "$remote_ver"
	log_ok "$PRODUCT_NAME v$remote_ver installed"
}

install_ide() {
	local product_id="ide"
	define_product_config "$product_id"

	if check_product "$product_id"; then
		return 0
	fi

	local remote_ver remote_url
	remote_ver=$(get_remote_version "$product_id")
	remote_url=$(get_remote_url "$product_id")

	if [ -z "$remote_url" ]; then
		log_error "Could not find download URL for $PRODUCT_NAME"
		return 1
	fi

	if ! check_disk_space 600 "$(dirname "$PRODUCT_INSTALL_ROOT")"; then
		return 1
	fi

	log_info "Installing $PRODUCT_NAME v$remote_ver..."
	log_verbose "Download URL: $remote_url"

	if [ "$DRY_RUN" -eq 1 ]; then
		log_dryrun "Would download and install $PRODUCT_NAME v$remote_ver"
		update_manifest_entry "$product_id" "$remote_ver"
		return 0
	fi

	ensure_tmpdir
	local archive="$TMPDIR/antigravity-ide.tar.gz"
	download_with_retry "$archive" "$remote_url" || return 1

	local extract_dir="$TMPDIR/extract"
	mkdir -p "$extract_dir"
	tar -xzf "$archive" -C "$extract_dir"

	if [ ! -d "$extract_dir/$PRODUCT_ARCHIVE_DIR" ]; then
		log_error "Unexpected archive structure: expected '$PRODUCT_ARCHIVE_DIR'"
		return 1
	fi

	if [ ! -x "$extract_dir/$PRODUCT_ARCHIVE_DIR/$PRODUCT_BINARY_NAME" ]; then
		log_error "$PRODUCT_BINARY_NAME not found or not executable in archive"
		return 1
	fi

	local icon_source="$extract_dir/$PRODUCT_ARCHIVE_DIR/$PRODUCT_ICON_SOURCE"
	if [ -f "$icon_source" ]; then
		mkdir -p "$(dirname "$PRODUCT_ICON_FILE")"
		install -m 0644 "$icon_source" "$PRODUCT_ICON_FILE"
		log_verbose "Icon installed to $PRODUCT_ICON_FILE"
	fi

	atomic_staging_install "$product_id" "$extract_dir" ""

	cat > "$PRODUCT_DESKTOP_FILE" <<DESKTOP
[Desktop Entry]
Name=$PRODUCT_NAME
Comment=Google $PRODUCT_NAME
Exec=$PRODUCT_COMMAND_LINK %U
Icon=antigravity-ide
Terminal=false
Type=Application
Categories=Development;IDE;
MimeType=x-scheme-handler/antigravity-ide;application/x-antigravity-workspace;
StartupNotify=true
StartupWMClass=$PRODUCT_WM_CLASS
DESKTOP
	log_verbose "Desktop entry written to $PRODUCT_DESKTOP_FILE"

	update_manifest_entry "$product_id" "$remote_ver"
	log_ok "$PRODUCT_NAME v$remote_ver installed"
}

install_cli() {
	local product_id="cli"
	define_product_config "$product_id"

	local remote_ver
	remote_ver=$(get_remote_version "$product_id")

	if [ -z "$remote_ver" ]; then
		remote_ver=$(curl -fsSL "$CLI_MANIFEST_BASE/linux_amd64.json" 2>/dev/null | \
			python3 -c "import json,sys; print(json.load(sys.stdin).get('version',''))" 2>/dev/null || echo "")
	fi

	if [ "$FORCE" -ne 1 ] && [ -x "$PRODUCT_CLI_BINARY_PATH" ]; then
		local installed_ver
		installed_ver=$(get_installed_version "$product_id")
		log_ok "$PRODUCT_NAME already installed at $PRODUCT_CLI_BINARY_PATH"
		if [ -n "$remote_ver" ] && [ "$installed_ver" != "$remote_ver" ]; then
			log_info "$PRODUCT_NAME is self-updating. Run 'agy update' to get v$remote_ver."
		fi
		return 0
	fi

	log_info "Installing $PRODUCT_NAME v${remote_ver:-latest}..."

	if [ "$DRY_RUN" -eq 1 ]; then
		log_dryrun "Would run CLI installer script"
		update_manifest_entry "$product_id" "${remote_ver:-latest}"
		return 0
	fi

	ensure_tmpdir
	local cli_script="$TMPDIR/install-cli.sh"
	download_with_retry "$cli_script" "$CLI_INSTALL_URL" || return 1

	if [ ! -s "$cli_script" ]; then
		log_error "Downloaded CLI installer is empty"
		return 1
	fi

	local cli_args=()
	if [ "$USER_MODE" -eq 1 ] || [ -n "${CUSTOM_CLI_DIR:-}" ]; then
		local cli_dir="${CUSTOM_CLI_DIR:-$HOME/.local/bin}"
		cli_args=("--dir" "$cli_dir")
	fi

	log_verbose "Running CLI installer..."
	if ! bash "$cli_script" "${cli_args[@]}"; then
		log_error "CLI installation failed"
		return 1
	fi

	local actual_binary
	if [ "$USER_MODE" -eq 1 ]; then
		actual_binary="$HOME/.local/bin/agy"
	elif [ -n "${CUSTOM_CLI_DIR:-}" ]; then
		actual_binary="$CUSTOM_CLI_DIR/agy"
	else
		actual_binary="$HOME/.local/bin/agy"
	fi

	if [ ! -x "$actual_binary" ]; then
		log_error "CLI binary not found at $actual_binary after installation"
		return 1
	fi

	if [ "$USER_MODE" -eq 0 ] && [ "$actual_binary" != "$PRODUCT_CLI_BINARY_PATH" ]; then
		log_warn "CLI installed to $actual_binary (user home). Use --user for user-mode installs."
	fi

	update_manifest_entry "$product_id" "${remote_ver:-latest}"
	log_ok "$PRODUCT_NAME v${remote_ver:-latest} installed to $actual_binary"
	log_info "Run 'agy --help' to get started."
}

install_sdk() {
	local product_id="sdk"
	define_product_config "$product_id"

	local remote_ver
	remote_ver=$(get_remote_version "$product_id")

	if [ "$FORCE" -ne 1 ]; then
		if pipx list --short 2>/dev/null | grep -q "^$SDK_PACKAGE"; then
			log_ok "$PRODUCT_NAME already installed via pipx"
			return 0
		fi
		if pip show "$SDK_PACKAGE" >/dev/null 2>&1; then
			log_ok "$PRODUCT_NAME already installed via pip"
			return 0
		fi
	fi

	log_info "Installing $PRODUCT_NAME v${remote_ver:-latest}..."

	if [ "$DRY_RUN" -eq 1 ]; then
		if command -v pipx >/dev/null 2>&1; then
			log_dryrun "Would run: pipx install $SDK_PACKAGE"
		else
			log_dryrun "Would run: pip install --user $SDK_PACKAGE"
		fi
		update_manifest_entry "$product_id" "${remote_ver:-latest}"
		return 0
	fi

	if command -v pipx >/dev/null 2>&1; then
		log_info "Using pipx for isolated installation..."
		if ! pipx install "$SDK_PACKAGE" 2>&1; then
			log_error "pipx install failed"
			return 1
		fi
	else
		log_info "Using pip --user installation..."
		if ! pip install --user "$SDK_PACKAGE" 2>&1; then
			log_error "pip install failed"
			return 1
		fi
	fi

	local installed_version
	installed_version=$(pip show "$SDK_PACKAGE" 2>/dev/null | awk '/^Version:/{print $2}' || \
		pipx runpip "$SDK_PACKAGE" show "$SDK_PACKAGE" 2>/dev/null | awk '/^Version:/{print $2}' || \
		echo "${remote_ver:-unknown}")

	update_manifest_entry "$product_id" "${installed_version:-${remote_ver:-unknown}}"
	log_ok "$PRODUCT_NAME v${installed_version:-${remote_ver:-unknown}} installed"
}

install_product() {
	local product_id="$1"
	log_verbose "--- Processing $product_id ---"

	case "$product_id" in
		antigravity) install_antigravity ;;
		ide)         install_ide ;;
		cli)         install_cli ;;
		sdk)         install_sdk ;;
		*) log_error "Unknown product: $product_id"; return 1 ;;
	esac
}

uninstall_product() {
	local product_id="$1"
	define_product_config "$product_id"

	local installed_ver
	installed_ver=$(get_installed_version "$product_id")

	if [ -z "$installed_ver" ] && [ "$FORCE" -ne 1 ]; then
		log_warn "$PRODUCT_NAME is not installed"
		return 0
	fi

	log_info "Uninstalling $PRODUCT_NAME..."

	if [ "$DRY_RUN" -eq 1 ]; then
		log_dryrun "Would uninstall $PRODUCT_NAME"
		remove_manifest_entry "$product_id"
		return 0
	fi

	case "$product_id" in
		antigravity|ide)
			if [ -d "$PRODUCT_INSTALL_ROOT" ]; then
				rotate_backups "$PRODUCT_INSTALL_ROOT"
			fi
			if [ -L "$PRODUCT_COMMAND_LINK" ]; then rm -f "$PRODUCT_COMMAND_LINK"; fi
			if [ -f "$PRODUCT_DESKTOP_FILE" ]; then rm -f "$PRODUCT_DESKTOP_FILE"; fi
			if [ -f "$PRODUCT_ICON_FILE" ]; then rm -f "$PRODUCT_ICON_FILE"; fi
			;;
		cli)
			local cli_bin="${PRODUCT_CLI_BINARY_PATH:-$HOME/.local/bin/agy}"
			if [ -f "$cli_bin" ]; then
				rm -f "$cli_bin"
				log_verbose "Removed $cli_bin"
			fi
			;;
		sdk)
			if pipx list --short 2>/dev/null | grep -q "^$SDK_PACKAGE"; then
				pipx uninstall "$SDK_PACKAGE" 2>/dev/null || true
			fi
			if pip show "$SDK_PACKAGE" >/dev/null 2>&1; then
				pip uninstall -y "$SDK_PACKAGE" 2>/dev/null || true
			fi
			;;
	esac

	remove_manifest_entry "$product_id"
	log_ok "$PRODUCT_NAME uninstalled"
}

list_products() {
	local products=("antigravity" "ide" "cli" "sdk")

	printf "\n${BOLD}%-22s  %-16s  %-14s  %-14s${NC}\n" \
		"Product" "Status" "Installed" "Available"
	printf "%.0s─" {1..75}
	printf "\n"

	for pid in "${products[@]}"; do
		define_product_config "$pid"
		local remote_ver installed_ver status
		remote_ver=$(get_remote_version "$pid")
		installed_ver=$(get_installed_version "$pid")

		if [ -z "$remote_ver" ]; then
			remote_ver="?"
		fi

		if [ -n "$installed_ver" ]; then
			if [ "$installed_ver" = "$remote_ver" ]; then
				status="${GREEN}Up to date${NC}"
			else
				status="${YELLOW}Update avail${NC}"
			fi
			local installed_display="v$installed_ver"
		else
			status="Not installed"
			installed_display="--"
		fi

		printf "%-22s  %b  %-14s  v%-13s\n" \
			"$PRODUCT_NAME" "$status" "$installed_display" "$remote_ver"
	done
	printf "\n"
}

post_install_hooks() {
	if [ "$USER_MODE" -eq 1 ] || [ "$DRY_RUN" -eq 1 ]; then
		return 0
	fi

	if command -v update-desktop-database >/dev/null 2>&1; then
		update-desktop-database "$DATA_PREFIX/applications" >/dev/null 2>&1 || true
	fi
	if command -v gtk-update-icon-cache >/dev/null 2>&1; then
		gtk-update-icon-cache -q "$DATA_PREFIX/icons/hicolor" 2>/dev/null || true
	fi
}

announce_updates() {
	[ "$QUIET" -eq 1 ] && return 0
	[ "$MODE" = "list" ] && return 0

	local changed=0
	for pid in "${SELECTED_PRODUCTS[@]}"; do
		local remote_ver installed_ver
		remote_ver=$(get_remote_version "$pid")
		installed_ver=$(get_installed_version "$pid")
		if [ -z "$installed_ver" ] || [ "$installed_ver" != "$remote_ver" ]; then
			changed=1
			break
		fi
	done

	if [ "$changed" -eq 1 ]; then
		echo ""
		echo -e "${BOLD}${GREEN}✓ Installation complete${NC}"
	fi
}

main() {
	if [ ! -t 0 ]; then
		PIPE_MODE=1
	fi

	detect_platform
	detect_distro

	if [ "$USER_MODE" -eq 1 ]; then
		OPT_PREFIX="$HOME/.local/opt"
		BIN_PREFIX="$HOME/.local/bin"
		DATA_PREFIX="$HOME/.local/share"
	else
		OPT_PREFIX="/opt"
		BIN_PREFIX="/usr/local/bin"
		DATA_PREFIX="/usr/share"
	fi

	if [ "$MODE" = "list" ]; then
		ensure_tmpdir
		extract_all_products
		list_products
		exit 0
	fi

	if [ ${#SELECTED_PRODUCTS[@]} -eq 0 ]; then
		if [ "$PIPE_MODE" -eq 1 ]; then
			log_warn "No products specified. Use: curl ... | bash -s -- --install PRODUCT"
			log_warn "Valid products: antigravity, ide, cli, sdk, all"
			exit 1
		fi
		ensure_tmpdir
		extract_all_products
		interactive_menu

		if [ "$MODE" = "update" ]; then
			MODE="install"
			local manifest installed
			manifest=$(read_manifest)
			installed=$(echo "$manifest" | python3 -c "
import json, sys
d = json.load(sys.stdin)
ids = [k for k in d.get('products', {}) if d['products'][k].get('version')]
print(' '.join(ids))
" 2>/dev/null || echo "")
			SELECTED_PRODUCTS=()
			for pid in $installed; do
				SELECTED_PRODUCTS+=("$pid")
			done
			if [ ${#SELECTED_PRODUCTS[@]} -eq 0 ]; then
				log_warn "No products installed."
				exit 0
			fi
		fi
	fi

	if [ -z "$PRODUCTS_JSON" ]; then
		ensure_tmpdir
		extract_all_products
	fi

	case "$MODE" in
		install)
			check_root
			check_deps
			local need_glibc_check=0
			for pid in "${SELECTED_PRODUCTS[@]}"; do
				case "$pid" in antigravity|ide) need_glibc_check=1 ;; esac
			done
			if [ "$need_glibc_check" -eq 1 ]; then
				check_glibc || exit 1
			fi
			for pid in "${SELECTED_PRODUCTS[@]}"; do
				install_product "$pid"
			done
			post_install_hooks
			announce_updates
			;;
		uninstall)
			check_root
			for pid in "${SELECTED_PRODUCTS[@]}"; do
				uninstall_product "$pid"
			done
			;;
	esac
}

if [ $# -eq 0 ]; then
	SELECTED_PRODUCTS=()
	MODE="install"
else
	parse_args "$@"
fi

main
