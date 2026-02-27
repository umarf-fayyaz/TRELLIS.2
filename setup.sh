#!/bin/bash

# Trellis2 Setup Script - Optimized for NVIDIA A10G with CUDA 13.0
# Exit on error
set -e

echo "=========================================="
echo "Trellis2 Installation Script"
echo "Detected: NVIDIA A10G with CUDA 13.0"
echo "=========================================="
echo ""

# Read Arguments
TEMP=`getopt -o h --long help,basic,flash-attn,cumesh,o-voxel,flexgemm,nvdiffrast,nvdiffrec,all -n 'setup.sh' -- "$@"`

eval set -- "$TEMP"

HELP=false
BASIC=false
FLASHATTN=false
CUMESH=false
OVOXEL=false
FLEXGEMM=false
NVDIFFRAST=false
NVDIFFREC=false
ALL=false
ERROR=false

if [ "$#" -eq 1 ] ; then
    HELP=true
fi

while true ; do
    case "$1" in
        -h|--help) HELP=true ; shift ;;
        --basic) BASIC=true ; shift ;;
        --flash-attn) FLASHATTN=true ; shift ;;
        --cumesh) CUMESH=true ; shift ;;
        --o-voxel) OVOXEL=true ; shift ;;
        --flexgemm) FLEXGEMM=true ; shift ;;
        --nvdiffrast) NVDIFFRAST=true ; shift ;;
        --nvdiffrec) NVDIFFREC=true ; shift ;;
        --all) ALL=true ; shift ;;
        --) shift ; break ;;
        *) ERROR=true ; break ;;
    esac
done

if [ "$ERROR" = true ] ; then
    echo "Error: Invalid argument"
    HELP=true
fi

if [ "$HELP" = true ] ; then
    echo "Usage: ./setup.sh [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  -h, --help              Display this help message"
    echo "  --basic                 Install basic dependencies"
    echo "  --flash-attn            Install flash-attention (CUDA optimized)"
    echo "  --cumesh                Install cumesh"
    echo "  --o-voxel               Install o-voxel"
    echo "  --flexgemm              Install flexgemm"
    echo "  --nvdiffrast            Install nvdiffrast"
    echo "  --nvdiffrec             Install nvdiffrec"
    echo "  --all                   Install all components"
    echo ""
    echo "Examples:"
    echo "  ./setup.sh --basic --flash-attn"
    echo "  ./setup.sh --all"
    echo ""
    echo "Note: Make sure you've activated your conda environment first:"
    echo "  conda activate trellis2"
    exit 0
fi

# If --all flag is used, enable everything
if [ "$ALL" = true ] ; then
    BASIC=true
    FLASHATTN=true
    CUMESH=true
    FLEXGEMM=true
    NVDIFFRAST=true
    NVDIFFREC=true
    # OVOXEL requires local directory, so not included in --all
fi

# Get working directory
WORKDIR=$(pwd)
EXTENSIONS_DIR="/tmp/trellis2_extensions_$$"

# Cleanup function
cleanup() {
    if [ -d "$EXTENSIONS_DIR" ]; then
        echo "Cleaning up temporary directory..."
        rm -rf "$EXTENSIONS_DIR"
    fi
}
trap cleanup EXIT

# Check Python availability
if ! command -v python > /dev/null 2>&1; then
    echo "Error: Python not found!"
    echo "Please activate your conda environment first:"
    echo "  conda activate trellis2"
    exit 1
fi

PYTHON_VERSION=$(python --version 2>&1 | awk '{print $2}')
echo "Using Python $PYTHON_VERSION"
echo ""

# Check if PyTorch is installed, if not install it
if ! python -c "import torch" 2>/dev/null; then
    echo "PyTorch not detected. Installing PyTorch 2.6.0 for CUDA 12.4..."
    pip install torch==2.6.0 torchvision==0.21.0 --index-url https://download.pytorch.org/whl/cu124 || {
        echo "Error: Failed to install PyTorch"
        exit 1
    }
    echo "PyTorch installed successfully!"
    echo ""
else
    TORCH_VERSION=$(python -c "import torch; print(torch.__version__)")
    CUDA_AVAILABLE=$(python -c "import torch; print(torch.cuda.is_available())")
    echo "PyTorch $TORCH_VERSION detected (CUDA available: $CUDA_AVAILABLE)"
    echo ""
fi

# Install basic dependencies
if [ "$BASIC" = true ] ; then
    echo "=========================================="
    echo "Installing Basic Dependencies"
    echo "=========================================="
    
    echo "Installing core packages..."
    pip install imageio imageio-ffmpeg tqdm easydict opencv-python-headless ninja trimesh transformers gradio==6.0.1 tensorboard pandas lpips zstandard || {
        echo "Error: Failed to install basic Python packages"
        exit 1
    }
    
    echo "Installing utils3d..."
    pip install git+https://github.com/EasternJournalist/utils3d.git@9a4eb15e4021b67b12c460c7057d642626897ec8 || {
        echo "Error: Failed to install utils3d"
        exit 1
    }
    
    # Check for libjpeg-dev
    if dpkg -l | grep -q libjpeg-dev 2>/dev/null; then
        echo "libjpeg-dev already installed"
    else
        echo "Installing libjpeg-dev (requires sudo)..."
        sudo apt install -y libjpeg-dev || {
            echo "Warning: Failed to install libjpeg-dev. Continuing anyway..."
        }
    fi
    
    echo "Installing pillow-simd..."
    pip install pillow-simd || {
        echo "Warning: Failed to install pillow-simd, falling back to pillow"
        pip install pillow
    }
    
    echo "Installing kornia and timm..."
    pip install kornia timm || {
        echo "Error: Failed to install kornia and timm"
        exit 1
    }
    
    echo "✓ Basic dependencies installed successfully!"
    echo ""
fi

# Install flash-attention
if [ "$FLASHATTN" = true ] ; then
    echo "=========================================="
    echo "Installing Flash-Attention"
    echo "=========================================="
    
    # Check if already installed
    if python -c "import flash_attn" 2>/dev/null; then
        echo "Flash-attention already installed"
        FLASH_VERSION=$(python -c "import flash_attn; print(flash_attn.__version__)" 2>/dev/null || echo "unknown")
        echo "Version: $FLASH_VERSION"
    else
        echo "Installing flash-attn 2.7.3 (optimized for A10G)..."
        echo "This may take 2-5 minutes..."
        
        pip install flash-attn==2.7.3 --no-build-isolation || {
            echo "Error: Failed to install flash-attn"
            echo "Note: Flash-attention requires CUDA toolkit to be installed"
            exit 1
        }
        
        # Verify installation
        if python -c "import flash_attn" 2>/dev/null; then
            echo "✓ Flash-attention installed successfully!"
        else
            echo "Error: Flash-attention installation verification failed"
            exit 1
        fi
    fi
    echo ""
fi

# Install nvdiffrast
if [ "$NVDIFFRAST" = true ] ; then
    echo "=========================================="
    echo "Installing nvdiffrast"
    echo "=========================================="
    
    if python -c "import nvdiffrast" 2>/dev/null; then
        echo "nvdiffrast already installed"
    else
        mkdir -p "$EXTENSIONS_DIR"
        echo "Cloning nvdiffrast repository..."
        git clone -b v0.4.0 https://github.com/NVlabs/nvdiffrast.git "$EXTENSIONS_DIR/nvdiffrast" || {
            echo "Error: Failed to clone nvdiffrast repository"
            exit 1
        }
        
        echo "Building and installing nvdiffrast..."
        pip install "$EXTENSIONS_DIR/nvdiffrast" --no-build-isolation || {
            echo "Error: Failed to install nvdiffrast"
            exit 1
        }
        
        if python -c "import nvdiffrast" 2>/dev/null; then
            echo "✓ nvdiffrast installed successfully!"
        else
            echo "Error: nvdiffrast installation verification failed"
            exit 1
        fi
    fi
    echo ""
fi

# Install nvdiffrec
if [ "$NVDIFFREC" = true ] ; then
    echo "=========================================="
    echo "Installing nvdiffrec"
    echo "=========================================="
    
    if python -c "import nvdiffrec" 2>/dev/null; then
        echo "nvdiffrec already installed"
    else
        mkdir -p "$EXTENSIONS_DIR"
        echo "Cloning nvdiffrec repository..."
        git clone -b renderutils https://github.com/JeffreyXiang/nvdiffrec.git "$EXTENSIONS_DIR/nvdiffrec" || {
            echo "Error: Failed to clone nvdiffrec repository"
            exit 1
        }
        
        echo "Building and installing nvdiffrec..."
        pip install "$EXTENSIONS_DIR/nvdiffrec" --no-build-isolation || {
            echo "Error: Failed to install nvdiffrec"
            exit 1
        }
        
        if python -c "import nvdiffrec" 2>/dev/null; then
            echo "✓ nvdiffrec installed successfully!"
        else
            echo "Error: nvdiffrec installation verification failed"
            exit 1
        fi
    fi
    echo ""
fi

# Install CuMesh
if [ "$CUMESH" = true ] ; then
    echo "=========================================="
    echo "Installing CuMesh"
    echo "=========================================="
    
    if python -c "import cumesh" 2>/dev/null; then
        echo "CuMesh already installed"
    else
        mkdir -p "$EXTENSIONS_DIR"
        echo "Cloning CuMesh repository..."
        git clone https://github.com/JeffreyXiang/CuMesh.git "$EXTENSIONS_DIR/CuMesh" --recursive || {
            echo "Error: Failed to clone CuMesh repository"
            exit 1
        }
        
        echo "Building and installing CuMesh..."
        pip install "$EXTENSIONS_DIR/CuMesh" --no-build-isolation || {
            echo "Error: Failed to install CuMesh"
            exit 1
        }
        
        if python -c "import cumesh" 2>/dev/null; then
            echo "✓ CuMesh installed successfully!"
        else
            echo "Error: CuMesh installation verification failed"
            exit 1
        fi
    fi
    echo ""
fi

# Install FlexGEMM
if [ "$FLEXGEMM" = true ] ; then
    echo "=========================================="
    echo "Installing FlexGEMM"
    echo "=========================================="
    
    if python -c "import flexgemm" 2>/dev/null; then
        echo "FlexGEMM already installed"
    else
        mkdir -p "$EXTENSIONS_DIR"
        echo "Cloning FlexGEMM repository..."
        git clone https://github.com/JeffreyXiang/FlexGEMM.git "$EXTENSIONS_DIR/FlexGEMM" --recursive || {
            echo "Error: Failed to clone FlexGEMM repository"
            exit 1
        }
        
        echo "Building and installing FlexGEMM..."
        pip install "$EXTENSIONS_DIR/FlexGEMM" --no-build-isolation || {
            echo "Error: Failed to install FlexGEMM"
            exit 1
        }
        
        if python -c "import flexgemm" 2>/dev/null; then
            echo "✓ FlexGEMM installed successfully!"
        else
            echo "Error: FlexGEMM installation verification failed"
            exit 1
        fi
    fi
    echo ""
fi

# Install o-voxel
if [ "$OVOXEL" = true ] ; then
    echo "=========================================="
    echo "Installing o-voxel"
    echo "=========================================="
    
    if [ ! -d "o-voxel" ]; then
        echo "Error: o-voxel directory not found in current directory ($WORKDIR)"
        echo "Please make sure the o-voxel directory exists before running this option."
        exit 1
    fi
    
    if python -c "import ovoxel" 2>/dev/null; then
        echo "o-voxel already installed"
    else
        mkdir -p "$EXTENSIONS_DIR"
        echo "Copying o-voxel directory..."
        cp -r o-voxel "$EXTENSIONS_DIR/o-voxel" || {
            echo "Error: Failed to copy o-voxel directory"
            exit 1
        }
        
        echo "Building and installing o-voxel..."
        pip install "$EXTENSIONS_DIR/o-voxel" --no-build-isolation || {
            echo "Error: Failed to install o-voxel"
            exit 1
        }
        
        if python -c "import ovoxel" 2>/dev/null; then
            echo "✓ o-voxel installed successfully!"
        else
            echo "Error: o-voxel installation verification failed"
            exit 1
        fi
    fi
    echo ""
fi

echo ""
echo "=========================================="
echo "✓ Installation Completed Successfully!"
echo "=========================================="
echo ""
echo "Installed components:"
[ "$BASIC" = true ] && echo "  ✓ Basic dependencies"
[ "$FLASHATTN" = true ] && echo "  ✓ Flash-attention"
[ "$NVDIFFRAST" = true ] && echo "  ✓ nvdiffrast"
[ "$NVDIFFREC" = true ] && echo "  ✓ nvdiffrec"
[ "$CUMESH" = true ] && echo "  ✓ CuMesh"
[ "$FLEXGEMM" = true ] && echo "  ✓ FlexGEMM"
[ "$OVOXEL" = true ] && echo "  ✓ o-voxel"
echo ""
echo "You can now use Trellis2!"
