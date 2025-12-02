#!/bin/bash
#
# MakeGIF Installer
# https://github.com/nathan-kennedy/makegif
#

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m' # No Color

INSTALL_DIR="$HOME/.local/share/makegif"
SCRIPT_URL="https://raw.githubusercontent.com/dissidentcode/makegif/master/makegif.sh"

print_banner() {
    echo -e "${BLUE}${BOLD}"
    echo "  __  __       _         ____ ___ _____ "
    echo " |  \/  | __ _| | _____ / ___|_ _|  ___|"
    echo " | |\/| |/ _\` | |/ / _ \| |  _ | || |_   "
    echo " | |  | | (_| |   <  __/| |_| || ||  _|  "
    echo " |_|  |_|\__,_|_|\_\___| \____|___|_|    "
    echo -e "${NC}"
    echo -e "${BOLD}Video to GIF converter${NC}"
    echo ""
}

info() {
    echo -e "${BLUE}==>${NC} ${BOLD}$1${NC}"
}

success() {
    echo -e "${GREEN}✓${NC} $1"
}

warn() {
    echo -e "${YELLOW}!${NC} $1"
}

error() {
    echo -e "${RED}✗${NC} $1"
}

# Detect the user's shell
detect_shell() {
    if [ -n "$ZSH_VERSION" ] || [ "$SHELL" = "/bin/zsh" ] || [ "$SHELL" = "/usr/bin/zsh" ]; then
        echo "zsh"
    elif [ -n "$BASH_VERSION" ] || [ "$SHELL" = "/bin/bash" ] || [ "$SHELL" = "/usr/bin/bash" ]; then
        echo "bash"
    else
        echo "unknown"
    fi
}

# Get the appropriate rc file
get_rc_file() {
    local shell_type="$1"
    case "$shell_type" in
        zsh)
            echo "$HOME/.zshrc"
            ;;
        bash)
            if [ -f "$HOME/.bashrc" ]; then
                echo "$HOME/.bashrc"
            elif [ -f "$HOME/.bash_profile" ]; then
                echo "$HOME/.bash_profile"
            else
                echo "$HOME/.bashrc"
            fi
            ;;
        *)
            echo ""
            ;;
    esac
}

# Detect package manager
detect_package_manager() {
    if command -v brew &> /dev/null; then
        echo "brew"
    elif command -v apt-get &> /dev/null; then
        echo "apt"
    elif command -v dnf &> /dev/null; then
        echo "dnf"
    elif command -v yum &> /dev/null; then
        echo "yum"
    elif command -v pacman &> /dev/null; then
        echo "pacman"
    else
        echo "unknown"
    fi
}

# Check if a command exists
has_command() {
    command -v "$1" &> /dev/null
}

# Install dependencies
install_dependencies() {
    local pkg_manager="$1"
    local missing=()

    if ! has_command ffmpeg; then
        missing+=("ffmpeg")
    fi
    if ! has_command gifsicle; then
        missing+=("gifsicle")
    fi

    if [ ${#missing[@]} -eq 0 ]; then
        success "All dependencies already installed"
        return 0
    fi

    warn "Missing dependencies: ${missing[*]}"
    echo ""

    if [ "$pkg_manager" = "unknown" ]; then
        error "Could not detect package manager"
        echo "  Please install manually: ffmpeg gifsicle"
        return 1
    fi

    echo -e -n "  Install ${missing[*]} using ${BOLD}$pkg_manager${NC}? [y/N] "
    read -r response
    if [[ ! "$response" =~ ^[Yy]$ ]]; then
        warn "Skipping dependency installation"
        echo "  You'll need to install these manually: ${missing[*]}"
        return 0
    fi

    info "Installing dependencies..."

    case "$pkg_manager" in
        brew)
            brew install "${missing[@]}"
            ;;
        apt)
            sudo apt-get update && sudo apt-get install -y "${missing[@]}"
            ;;
        dnf)
            sudo dnf install -y "${missing[@]}"
            ;;
        yum)
            sudo yum install -y "${missing[@]}"
            ;;
        pacman)
            sudo pacman -S --noconfirm "${missing[@]}"
            ;;
    esac

    if [ $? -eq 0 ]; then
        success "Dependencies installed"
    else
        error "Failed to install some dependencies"
        return 1
    fi
}

# Main installation
main() {
    print_banner

    # Detect shell
    info "Detecting shell..."
    local user_shell
    user_shell=$(detect_shell)

    if [ "$user_shell" = "unknown" ]; then
        error "Could not detect your shell (bash/zsh)"
        echo "  Please add this line to your shell config manually:"
        echo "  source \"$INSTALL_DIR/makegif.sh\""
        exit 1
    fi
    success "Detected shell: $user_shell"

    local rc_file
    rc_file=$(get_rc_file "$user_shell")

    # Create install directory
    info "Creating install directory..."
    mkdir -p "$INSTALL_DIR"
    success "Created $INSTALL_DIR"

    # Download makegif.sh
    info "Downloading makegif.sh..."
    if curl -sSL "$SCRIPT_URL" -o "$INSTALL_DIR/makegif.sh"; then
        success "Downloaded makegif.sh"
    else
        error "Failed to download makegif.sh"
        exit 1
    fi

    # Add source line to rc file
    info "Configuring shell..."
    local source_line="source \"$INSTALL_DIR/makegif.sh\""

    if [ -f "$rc_file" ] && grep -q "makegif.sh" "$rc_file"; then
        success "Already configured in $rc_file"
    else
        # Backup rc file
        if [ -f "$rc_file" ]; then
            cp "$rc_file" "$rc_file.backup.$(date +%Y%m%d%H%M%S)"
        fi

        echo "" >> "$rc_file"
        echo "# MakeGIF - Video to GIF converter" >> "$rc_file"
        echo "$source_line" >> "$rc_file"
        success "Added to $rc_file"
    fi

    # Install dependencies
    echo ""
    info "Checking dependencies..."
    local pkg_manager
    pkg_manager=$(detect_package_manager)
    install_dependencies "$pkg_manager"

    # Done!
    echo ""
    echo -e "${GREEN}${BOLD}Installation complete!${NC}"
    echo ""
    echo "To start using makegif, either:"
    echo "  1. Open a new terminal window, or"
    echo "  2. Run: source $rc_file"
    echo ""
    echo "Then try:"
    echo -e "  ${BOLD}makegif${NC}          # Interactive mode with TUI"
    echo -e "  ${BOLD}makegif --help${NC}   # See all options"
    echo ""
}

main "$@"
