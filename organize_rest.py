import os
import shutil

# Dictionary mapping Invoice No -> List of file paths
invoice_mapping = {
    # 6ST6 folder
    "NIV3594182600261": [
        r"d:\MeridianDist\data\6ST6\IMG_20260613_184132717_HDR.jpg.jpeg",
        r"d:\MeridianDist\data\6ST6\IMG_20260613_184132717_HDR.jpg (1).jpeg",
    ],
    "NIV3594182600267": [
        r"d:\MeridianDist\data\6ST6\IMG_20260613_184143799_HDR.jpg.jpeg",
        r"d:\MeridianDist\data\6ST6\IMG_20260613_184151236_HDR.jpg.jpeg",
    ],
    "NIV3594182600268": [
        r"d:\MeridianDist\data\6ST6\IMG_20260613_184207558_HDR.jpg.jpeg",
    ],
    "CAD_15442": [
        r"d:\MeridianDist\data\6ST6\IMG_20260613_184221375_HDR.jpg.jpeg",
    ],
    "CAD_15455": [
        r"d:\MeridianDist\data\6ST6\IMG_20260613_184230429_HDR.jpg.jpeg",
        r"d:\MeridianDist\data\6ST6\IMG_20260613_184237176_HDR.jpg.jpeg",
        r"d:\MeridianDist\data\6ST6\IMG_20260613_184245849_HDR.jpg.jpeg",
    ],
    "CAD_15449": [
        r"d:\MeridianDist\data\6ST6\IMG_20260613_184255662_HDR.jpg.jpeg",
    ],
    "CAD_15462": [
        r"d:\MeridianDist\data\6ST6\IMG_20260613_184305103_HDR.jpg.jpeg",
        r"d:\MeridianDist\data\6ST6\IMG_20260613_184313537_HDR.jpg.jpeg",
    ],
    "DBR07283": [
        r"d:\MeridianDist\data\6ST6\IMG_20260613_184323080_HDR.jpg.jpeg",
    ],
    "DBR07285": [
        r"d:\MeridianDist\data\6ST6\IMG_20260613_184330257_HDR.jpg.jpeg",
        r"d:\MeridianDist\data\6ST6\IMG_20260613_184335529_HDR.jpg.jpeg",
    ],
    "A260000218": [
        r"d:\MeridianDist\data\6ST6\IMG_20260613_184346887_HDR.jpg.jpeg",
        r"d:\MeridianDist\data\6ST6\IMG_20260613_184353026_HDR.jpg.jpeg",
    ],
    "A260000223": [
        r"d:\MeridianDist\data\6ST6\IMG_20260613_184403983_HDR.jpg.jpeg",
    ],
    
    # Root data folder
    "GST05102": [
        r"d:\MeridianDist\data\IMG_20260613_184021352_HDR.jpg.jpeg",
        r"d:\MeridianDist\data\IMG_20260613_184031705_HDR.jpg.jpeg",
        r"d:\MeridianDist\data\IMG_20260613_184041542_HDR.jpg.jpeg",
    ],
    "GST05095": [
        r"d:\MeridianDist\data\IMG_20260613_184052766_HDR.jpg.jpeg",
        r"d:\MeridianDist\data\IMG_20260613_184055273_HDR.jpg.jpeg",
        r"d:\MeridianDist\data\IMG_20260613_184103009_HDR.jpg.jpeg",
    ],
    "GST05096": [
        r"d:\MeridianDist\data\IMG_20260613_184115157_HDR.jpg.jpeg",
        r"d:\MeridianDist\data\IMG_20260613_184120606_HDR.jpg.jpeg",
    ]
}

def main():
    base_dir = r"d:\MeridianDist\data"
    for invoice_no, files in invoice_mapping.items():
        # Create folder for invoice
        invoice_dir = os.path.join(base_dir, invoice_no)
        os.makedirs(invoice_dir, exist_ok=True)
        
        # Copy files to invoice folder
        for file_path in files:
            if os.path.exists(file_path):
                filename = os.path.basename(file_path)
                dest_path = os.path.join(invoice_dir, filename)
                shutil.copy2(file_path, dest_path)
                print(f"Copied {filename} to {invoice_no}")
            else:
                print(f"Warning: File not found {file_path}")

if __name__ == "__main__":
    main()
