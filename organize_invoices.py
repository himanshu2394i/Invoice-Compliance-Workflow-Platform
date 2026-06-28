import os
import shutil
import re
from PIL import Image
import pytesseract

def organize_invoices(data_dir):
    print(f"Organizing invoices in {data_dir}...")
    images = [f for f in os.listdir(data_dir) if f.lower().endswith(('.jpg', '.jpeg', '.png'))]
    images.sort()
    
    current_invoice = None
    
    for img_name in images:
        img_path = os.path.join(data_dir, img_name)
        try:
            # Perform OCR on the image with basic preprocessing
            image = Image.open(img_path).convert('L') # grayscale
            # Scale up to improve OCR
            width, height = image.size
            image = image.resize((width*2, height*2), Image.Resampling.LANCZOS)
            
            text = pytesseract.image_to_string(image)
            
            # Look for Invoice numbers starting with NIV (e.g. NIV3594182600261)
            # Or GST invoice numbers starting with GST (e.g. GST05095)
            # Handle common OCR typos like NlV, MIV, 6ST, etc.
            match = re.search(r'([NnMm][Il1][Vv]\s*\d+|[Gg6][Ss5][Tt]\s*\d+)', text)
            if not match:
                # Try with spaces
                match2 = re.search(r'(NIV\s*\d+|GST\s*\d+)', text)
                if match2:
                    current_invoice = match2.group(0).replace(" ", "")
            else:
                current_invoice = match.group(0)
                
            if current_invoice:
                # Create directory if it doesn't exist
                invoice_dir = os.path.join(data_dir, current_invoice)
                if not os.path.exists(invoice_dir):
                    os.makedirs(invoice_dir)
                    print(f"Created folder: {current_invoice}")
                
                # Move the image
                dest_path = os.path.join(invoice_dir, img_name)
                shutil.move(img_path, dest_path)
                print(f"Moved {img_name} to {current_invoice}/")
            else:
                print(f"Could not find invoice number in {img_name}")
                print(f"--- Raw OCR excerpt ---\n{text[:200]}\n-----------------------")
                
        except Exception as e:
            print(f"Error processing {img_name}: {e}")

if __name__ == "__main__":
    # If tesseract is installed but not in PATH, tell pytesseract where it is
    tesseract_paths = [
        r'C:\Program Files\Tesseract-OCR\tesseract.exe',
        r'C:\Program Files (x86)\Tesseract-OCR\tesseract.exe',
        r'C:\Users\Himanshu\AppData\Local\Programs\Tesseract-OCR\tesseract.exe',
        r'D:\Himanshu\Tesseract-OCR\tesseract.exe',
        r'D:\Himanshu\tesseract.exe',
        r'D:\Himanshu\Tesseract\tesseract.exe'
    ]
    for path in tesseract_paths:
        if os.path.exists(path):
            pytesseract.pytesseract.tesseract_cmd = path
            break

    data_directory = r"d:\MeridianDist\data"
    organize_invoices(data_directory)
    print("Done organizing invoices.")
