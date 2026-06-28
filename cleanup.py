import os
import shutil
import glob

def main():
    base_dir = r"d:\MeridianDist\data"
    
    # Remove 6ST6 folder and its contents
    st6_dir = os.path.join(base_dir, "6ST6")
    if os.path.exists(st6_dir):
        shutil.rmtree(st6_dir)
        print(f"Removed folder {st6_dir}")
        
    # Remove 6St 12301 folder and its contents
    st12301_dir = os.path.join(base_dir, "6St 12301")
    if os.path.exists(st12301_dir):
        shutil.rmtree(st12301_dir)
        print(f"Removed folder {st12301_dir}")
        
    # Remove the remaining root level loose images that we mapped
    images_to_remove = [
        "IMG_20260613_184021352_HDR.jpg.jpeg",
        "IMG_20260613_184031705_HDR.jpg.jpeg",
        "IMG_20260613_184041542_HDR.jpg.jpeg",
        "IMG_20260613_184052766_HDR.jpg.jpeg",
        "IMG_20260613_184055273_HDR.jpg.jpeg",
        "IMG_20260613_184103009_HDR.jpg.jpeg",
        "IMG_20260613_184115157_HDR.jpg.jpeg",
        "IMG_20260613_184120606_HDR.jpg.jpeg"
    ]
    
    for filename in images_to_remove:
        filepath = os.path.join(base_dir, filename)
        if os.path.exists(filepath):
            os.remove(filepath)
            print(f"Removed file {filepath}")

if __name__ == "__main__":
    main()
