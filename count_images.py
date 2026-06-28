import os

def main():
    base_dir = r"d:\MeridianDist\data"
    counts = []
    
    # Iterate over all items in the base directory
    for item in sorted(os.listdir(base_dir)):
        item_path = os.path.join(base_dir, item)
        
        # Check if it's a directory
        if os.path.isdir(item_path):
            # Count the number of files in the directory
            files = [f for f in os.listdir(item_path) if os.path.isfile(os.path.join(item_path, f))]
            counts.append(f"- {item}: {len(files)} image(s)")
            
    # Write the result to a markdown file
    output_path = r"d:\MeridianDist\folder_counts.md"
    with open(output_path, "w") as f:
        f.write("# Image Counts per Invoice Folder\n\n")
        f.write("\n".join(counts))
        f.write("\n")
        
if __name__ == "__main__":
    main()
