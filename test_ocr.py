import os
import subprocess
import re
import sys

def test_ocr(image_path):
    tesseract_cmd = r'D:\Himanshu\tesseract.exe'
    try:
        # Run tesseract and capture stdout
        result = subprocess.run([tesseract_cmd, image_path, 'stdout'], capture_output=True, text=True, check=True)
        text = result.stdout
        
        # Look for Invoice No
        # Can be "Invoice No." or "Invoice No :" or "Invoice No" or "Invoice No."
        # Followed by alphanumeric like MORDE0031291, HELL01671, etc.
        matches = re.findall(r'Invoice\s*No\.?\s*[:\-]?\s*([A-Za-z0-9]+)', text, re.IGNORECASE)
        print(f"File: {os.path.basename(image_path)}")
        if matches:
            print(f"Found Invoice No: {matches[0]}")
        else:
            print("No Invoice No found.")
            # Let's print the first 500 characters to see what it read
            print("Snippet of text:")
            print(text[:500])
        print("-" * 40)
    except Exception as e:
        print(f"Error processing {image_path}: {e}")

if __name__ == '__main__':
    images = [
        r"d:\MeridianDist\data\6St 12301\IMG_20260613_184410960_HDR.jpg.jpeg",
        r"d:\MeridianDist\data\6St 12301\IMG_20260613_184507725_HDR.jpg.jpeg",
        r"d:\MeridianDist\data\6St 12301\IMG_20260613_184625865_HDR.jpg.jpeg"
    ]
    for img in images:
        test_ocr(img)
