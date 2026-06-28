import os
import shutil

# Dictionary mapping Invoice No -> List of file paths
invoice_mapping = {
    # 6St 12301 folder
    "MORDE0031289": [
        r"d:\MeridianDist\data\6St 12301\IMG_20260613_184410960_HDR.jpg.jpeg",
        r"d:\MeridianDist\data\6St 12301\IMG_20260613_184426854_HDR.jpg.jpeg",
        r"d:\MeridianDist\data\6St 12301\IMG_20260613_184441020_HDR.jpg.jpeg",
    ],
    "HAL08221": [
        r"d:\MeridianDist\data\6St 12301\IMG_20260613_184450786_HDR.jpg.jpeg",
        r"d:\MeridianDist\data\6St 12301\IMG_20260613_184459026_HDR.jpg.jpeg",
    ],
    "HAL08222": [
        r"d:\MeridianDist\data\6St 12301\IMG_20260613_184507725_HDR.jpg.jpeg",
        r"d:\MeridianDist\data\6St 12301\IMG_20260613_184517198_HDR.jpg.jpeg",
    ],
    "HAL08223": [
        r"d:\MeridianDist\data\6St 12301\IMG_20260613_184525656_HDR.jpg.jpeg",
        r"d:\MeridianDist\data\6St 12301\IMG_20260613_184531621_HDR.jpg.jpeg",
    ],
    "HELL01655": [
        r"d:\MeridianDist\data\6St 12301\IMG_20260613_184556840_HDR.jpg.jpeg",
        r"d:\MeridianDist\data\6St 12301\IMG_20260613_184605255_HDR.jpg.jpeg",
        r"d:\MeridianDist\data\6St 12301\IMG_20260613_184611579_HDR.jpg.jpeg",
    ],
    "HELL01673": [
        r"d:\MeridianDist\data\6St 12301\IMG_20260613_184617884_HDR.jpg.jpeg",
        r"d:\MeridianDist\data\6St 12301\IMG_20260613_184619059_HDR.jpg.jpeg",
        r"d:\MeridianDist\data\6St 12301\IMG_20260613_184625865_HDR.jpg.jpeg",
    ],
    "HELL01675": [
        r"d:\MeridianDist\data\6St 12301\IMG_20260613_184632376_HDR.jpg.jpeg",
    ],
    "HELL01690": [
        r"d:\MeridianDist\data\6St 12301\IMG_20260613_184639013_HDR.jpg.jpeg",
    ],
    "HAL08248": [
        r"d:\MeridianDist\data\6St 12301\IMG_20260613_184652598_HDR.jpg.jpeg",
        r"d:\MeridianDist\data\6St 12301\IMG_20260613_184659746_HDR.jpg.jpeg",
    ],
    "HAL08273": [
        r"d:\MeridianDist\data\6St 12301\IMG_20260613_184712699_HDR.jpg.jpeg",
    ],
    "HAL08244": [
        r"d:\MeridianDist\data\6St 12301\IMG_20260613_184718602_HDR.jpg.jpeg",
    ],
    "HAL08274": [
        r"d:\MeridianDist\data\6St 12301\IMG_20260613_184728651_HDR.jpg.jpeg",
        r"d:\MeridianDist\data\6St 12301\IMG_20260613_184734202_HDR.jpg.jpeg",
    ],
    "HYGIN014569": [
        r"d:\MeridianDist\data\6St 12301\WhatsApp Image 2026-06-13 at 21.20.40.jpeg",
        r"d:\MeridianDist\data\6St 12301\WhatsApp Image 2026-06-13 at 21.20.41 (2).jpeg",
        r"d:\MeridianDist\data\6St 12301\WhatsApp Image 2026-06-13 at 21.20.41.jpeg",
        r"d:\MeridianDist\data\6St 12301\WhatsApp Image 2026-06-13 at 21.20.42 (1).jpeg",
        r"d:\MeridianDist\data\6St 12301\WhatsApp Image 2026-06-13 at 21.20.42.jpeg",
        r"d:\MeridianDist\data\6St 12301\WhatsApp Image 2026-06-13 at 21.20.43.jpeg",
    ],
    "HYGIN014592": [
        r"d:\MeridianDist\data\6St 12301\WhatsApp Image 2026-06-13 at 21.20.41 (1).jpeg",
        r"d:\MeridianDist\data\6St 12301\WhatsApp Image 2026-06-13 at 21.20.44 (1).jpeg",
    ],
    "REHN000797": [
        r"d:\MeridianDist\data\6St 12301\WhatsApp Image 2026-06-13 at 21.20.43 (1).jpeg",
    ],
    "REHN000800": [
        r"d:\MeridianDist\data\6St 12301\WhatsApp Image 2026-06-13 at 21.20.43 (2).jpeg",
        r"d:\MeridianDist\data\6St 12301\WhatsApp Image 2026-06-13 at 21.20.44.jpeg",
    ],
    "HYGIN014593": [
        r"d:\MeridianDist\data\6St 12301\WhatsApp Image 2026-06-13 at 21.20.44 (2).jpeg",
    ],

    # P2 2018 folder (already mapped)
    "HAL08285": [
        r"d:\MeridianDist\data\P2 2018\IMG_20260613_184852928_HDR.jpg.jpeg",
        r"d:\MeridianDist\data\P2 2018\IMG_20260613_184900018_HDR.jpg.jpeg",
        r"d:\MeridianDist\data\P2 2018\IMG_20260613_184908070_HDR.jpg.jpeg",
        r"d:\MeridianDist\data\P2 2018\IMG_20260613_184915663_HDR.jpg.jpeg",
    ],
    "HAL08288": [
        r"d:\MeridianDist\data\P2 2018\IMG_20260613_184925769_HDR.jpg.jpeg",
        r"d:\MeridianDist\data\P2 2018\IMG_20260613_184931969_HDR.jpg.jpeg",
    ],
    "HAL08253": [
        r"d:\MeridianDist\data\P2 2018\IMG_20260613_184941913_HDR.jpg.jpeg",
    ],
    "HAL08254": [
        r"d:\MeridianDist\data\P2 2018\IMG_20260613_184949579_HDR.jpg.jpeg",
    ],
    "HAL08256": [
        r"d:\MeridianDist\data\P2 2018\IMG_20260613_184955745_HDR.jpg.jpeg",
    ],
    "HAL08283": [
        r"d:\MeridianDist\data\P2 2018\IMG_20260613_185002820_HDR.jpg.jpeg",
    ],
    "HAL08286": [
        r"d:\MeridianDist\data\P2 2018\IMG_20260613_185010612_HDR.jpg.jpeg",
    ],
    "HAL08287": [
        r"d:\MeridianDist\data\P2 2018\IMG_20260613_185019800_HDR.jpg.jpeg",
        r"d:\MeridianDist\data\P2 2018\IMG_20260613_185025700_HDR.jpg.jpeg",
    ],
    "HAL08250": [
        r"d:\MeridianDist\data\P2 2018\IMG_20260613_185040621_HDR.jpg.jpeg",
    ],
    "HAL08251": [
        r"d:\MeridianDist\data\P2 2018\IMG_20260613_185047809_HDR.jpg.jpeg",
    ],
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
