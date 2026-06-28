import os
import shutil

data_dir = r"d:\MeridianDist\data\6ST6"
os.chdir(data_dir)

folders = {
    "Zepto_NIV3594182600261": ["IMG_20260613_184132717_HDR.jpg (1).jpeg", "IMG_20260613_184132717_HDR.jpg.jpeg"],
    "NIV3594182600267": ["IMG_20260613_184143799_HDR.jpg.jpeg", "IMG_20260613_184151236_HDR.jpg.jpeg"],
    "Zepto_NIV3594182600268": ["IMG_20260613_184207558_HDR.jpg.jpeg"],
    "Elenta_Mart_CAD_15442": ["IMG_20260613_184221375_HDR.jpg.jpeg"],
    "Grocery_and_Green_CAD_15455": ["IMG_20260613_184230429_HDR.jpg.jpeg", "IMG_20260613_184237176_HDR.jpg.jpeg", "IMG_20260613_184245849_HDR.jpg.jpeg"],
    "Needs_Retail_CAD_15449": ["IMG_20260613_184255662_HDR.jpg.jpeg"],
    "Airplaza_CAD_15462": ["IMG_20260613_184305103_HDR.jpg.jpeg", "IMG_20260613_184313537_HDR.jpg.jpeg"],
    "Max_Hypermarket_DBR07283": ["IMG_20260613_184323080_HDR.jpg.jpeg"],
    "Airplaza_DBR07285": ["IMG_20260613_184330257_HDR.jpg.jpeg", "IMG_20260613_184335529_HDR.jpg.jpeg"],
    "Airplaza_A260000218": ["IMG_20260613_184346887_HDR.jpg.jpeg", "IMG_20260613_184353026_HDR.jpg.jpeg"],
    "Home_Shoppe_A260000223": ["IMG_20260613_184403983_HDR.jpg.jpeg"]
}

for folder, files in folders.items():
    if not os.path.exists(folder):
        os.makedirs(folder)
    for f in files:
        if os.path.exists(f):
            shutil.move(f, folder)
            print(f"Moved {f} to {folder}")
        else:
            print(f"File {f} not found")

print("Done")
