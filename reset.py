import os
import shutil

data_dir = r"d:\MeridianDist\data"
bad_dirs = ["6ST6", "6St 12301", "GST05102", "GST05095"]

for b in bad_dirs:
    p = os.path.join(data_dir, b)
    if os.path.exists(p):
        print(f"Restoring from {b}...")
        for f in os.listdir(p):
            src = os.path.join(p, f)
            dst = os.path.join(data_dir, f)
            shutil.move(src, dst)
        os.rmdir(p)
print("Reset complete!")
