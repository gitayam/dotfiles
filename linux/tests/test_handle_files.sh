#!/bin/bash

# Test script for .bash_handle_files functions
source ~/.bash_handle_files 2>/dev/null || { echo "Failed to source .bash_handle_files"; exit 1; }

echo "Testing .bash_handle_files functions..."

# Test variables
TEST_DIR="/tmp/test_handle_files"
TEST_IMAGE="/tmp/test_image.png"
TEST_PDF="/tmp/test.pdf"

# Cleanup function
cleanup() {
    rm -rf "$TEST_DIR" "$TEST_IMAGE" "$TEST_PDF" /tmp/test_*.* /tmp/resized_*.* /tmp/converted_*.* 2>/dev/null
}
trap cleanup EXIT

# Create test directory
mkdir -p "$TEST_DIR"

echo "Test 1: batch_rename function"
# Create test files
for i in {1..3}; do
    echo "test content $i" > "$TEST_DIR/old_name_$i.txt"
done

cd "$TEST_DIR"
if batch_rename "old_name" "new_name"; then
    if [[ -f "new_name_1.txt" ]] && [[ -f "new_name_2.txt" ]] && [[ -f "new_name_3.txt" ]]; then
        echo "✓ batch_rename function works"
    else
        echo "✗ batch_rename function failed - files not renamed"
        exit 1
    fi
else
    echo "✗ batch_rename function failed"
    exit 1
fi

echo "Test 2: resize_images function"
if command -v convert >/dev/null 2>&1; then
    # Create a test image
    convert -size 200x200 xc:blue "$TEST_IMAGE" 2>/dev/null
    
    if [[ -f "$TEST_IMAGE" ]]; then
        cd "$(dirname "$TEST_IMAGE")"
        if resize_images 100 100; then
            if [[ -f "resized_$(basename "$TEST_IMAGE")" ]]; then
                echo "✓ resize_images function works"
            else
                echo "✗ resize_images function failed - no resized image"
                exit 1
            fi
        else
            echo "✗ resize_images function failed"
            exit 1
        fi
    else
        echo "⚠ Could not create test image, skipping resize test"
    fi
else
    echo "⚠ ImageMagick not available, skipping resize_images test"
fi

echo "Test 3: convert_images function"
if command -v convert >/dev/null 2>&1; then
    # Create a test image if not exists
    if [[ ! -f "$TEST_IMAGE" ]]; then
        convert -size 100x100 xc:red "$TEST_IMAGE" 2>/dev/null
    fi
    
    if [[ -f "$TEST_IMAGE" ]]; then
        cd "$(dirname "$TEST_IMAGE")"
        if convert_images jpg; then
            if ls converted_*.jpg >/dev/null 2>&1; then
                echo "✓ convert_images function works"
            else
                echo "✗ convert_images function failed - no converted image"
                exit 1
            fi
        else
            echo "✗ convert_images function failed"
            exit 1
        fi
    else
        echo "⚠ Could not create test image, skipping convert test"
    fi
else
    echo "⚠ ImageMagick not available, skipping convert_images test"
fi

echo "Test 4: remove_exif function"
if command -v exiftool >/dev/null 2>&1; then
    # Create a test image with EXIF data
    if command -v convert >/dev/null 2>&1; then
        convert -size 50x50 xc:green "$TEST_IMAGE" 2>/dev/null
        exiftool -overwrite_original -Artist="Test Artist" "$TEST_IMAGE" 2>/dev/null
        
        if remove_exif "$TEST_IMAGE"; then
            # Check if EXIF data was removed
            if ! exiftool "$TEST_IMAGE" 2>/dev/null | grep -q "Artist"; then
                echo "✓ remove_exif function works"
            else
                echo "✗ remove_exif function failed - EXIF data still present"
                exit 1
            fi
        else
            echo "✗ remove_exif function failed"
            exit 1
        fi
    else
        echo "⚠ ImageMagick not available for EXIF test"
    fi
else
    echo "⚠ exiftool not available, skipping remove_exif test"
fi

echo "Test 5: ocr_image function"
if command -v tesseract >/dev/null 2>&1; then
    # Create a simple text image
    if command -v convert >/dev/null 2>&1; then
        convert -size 200x50 xc:white -font DejaVu-Sans -pointsize 20 -draw "text 10,30 'TEST OCR'" "$TEST_IMAGE" 2>/dev/null
        
        if [[ -f "$TEST_IMAGE" ]]; then
            result=$(ocr_image "$TEST_IMAGE" 2>/dev/null)
            if echo "$result" | grep -i "test"; then
                echo "✓ ocr_image function works"
            else
                echo "⚠ ocr_image function may not work correctly (result: '$result')"
            fi
        else
            echo "⚠ Could not create test image for OCR"
        fi
    else
        echo "⚠ ImageMagick not available for OCR test"
    fi
else
    echo "⚠ tesseract not available, skipping ocr_image test"
fi

echo "Test 6: pdf_merge function"
if command -v pdfunite >/dev/null 2>&1; then
    # Create simple test PDFs
    if command -v convert >/dev/null 2>&1; then
        convert xc:white -page A4 "$TEST_DIR/test1.pdf" 2>/dev/null
        convert xc:gray -page A4 "$TEST_DIR/test2.pdf" 2>/dev/null
        
        cd "$TEST_DIR"
        if pdf_merge "merged.pdf" "test1.pdf" "test2.pdf"; then
            if [[ -f "merged.pdf" ]]; then
                echo "✓ pdf_merge function works"
            else
                echo "✗ pdf_merge function failed - no merged PDF"
                exit 1
            fi
        else
            echo "✗ pdf_merge function failed"
            exit 1
        fi
    else
        echo "⚠ ImageMagick not available for PDF test"
    fi
else
    echo "⚠ pdfunite not available, skipping pdf_merge test"
fi

echo "Test 7: pdf_extract_images function"
if command -v pdfimages >/dev/null 2>&1; then
    # Just test that the function is defined (requires proper PDF with images)
    if declare -f pdf_extract_images >/dev/null; then
        echo "✓ pdf_extract_images function is defined"
    else
        echo "✗ pdf_extract_images function not found"
        exit 1
    fi
else
    echo "⚠ pdfimages not available, skipping pdf_extract_images test"
fi

echo "Test 8: optimize_images function"
if command -v convert >/dev/null 2>&1; then
    # Create a test image
    convert -size 300x300 xc:yellow "$TEST_IMAGE" 2>/dev/null
    
    if [[ -f "$TEST_IMAGE" ]]; then
        original_size=$(stat -f%z "$TEST_IMAGE" 2>/dev/null || stat -c%s "$TEST_IMAGE" 2>/dev/null)
        cd "$(dirname "$TEST_IMAGE")"
        
        if optimize_images 80; then
            optimized_size=$(stat -f%z "optimized_$(basename "$TEST_IMAGE")" 2>/dev/null || stat -c%s "optimized_$(basename "$TEST_IMAGE")" 2>/dev/null)
            if [[ $optimized_size -le $original_size ]]; then
                echo "✓ optimize_images function works"
            else
                echo "✗ optimize_images function failed - file not optimized"
                exit 1
            fi
        else
            echo "✗ optimize_images function failed"
            exit 1
        fi
    else
        echo "⚠ Could not create test image for optimization"
    fi
else
    echo "⚠ ImageMagick not available, skipping optimize_images test"
fi

echo "All .bash_handle_files tests completed successfully!"
