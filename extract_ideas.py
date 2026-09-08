import json
from bs4 import BeautifulSoup
import re

themes_to_extract = [
    'transportation & logistics',
    'disaster management',
    'medtech / biotech / healthtech',
    'miscellaneous',
    'agriculture, foodtech & rural development',
    'smart automation'
]

def clean_text(text):
    return text.strip()

with open('sih_tables.html', 'r', encoding='utf-8') as f:
    soup = BeautifulSoup(f.read(), 'html.parser')

tables = soup.find_all('table')
problem_statements = []

for table in tables:
    ps = {}
    for tr in table.find_all('tr'):
        cells = tr.find_all(['th', 'td'])
        if len(cells) == 2:
            key = cells[0].get_text(strip=True).replace(':', '')
            val = cells[1].get_text(strip=True)
            ps[key] = val
    if 'Problem Statement Title' in ps and 'Description' in ps:
        problem_statements.append(ps)

# Group by theme
grouped = {t: [] for t in themes_to_extract}

for ps in problem_statements:
    cat = ps.get('Category', '').strip().lower()
    if cat != 'software':
        continue
    theme = ps.get('Theme', '').strip().lower()
    
    # Try to match theme
    matched_theme = None
    for t in themes_to_extract:
        if t in theme or theme in t:
            matched_theme = t
            break
            
    if matched_theme:
        grouped[matched_theme].append(ps)

def suggest_tech_stack(title, description):
    text = (title + " " + description).lower()
    
    frontend = "React / Next.js"
    backend = "Node.js / Express or Python / FastAPI"
    database = "PostgreSQL"
    extra = []
    
    if "mobile" in text or "app" in text or "android" in text or "ios" in text:
        frontend = "Flutter or React Native (Mobile) + React.js (Web Admin)"
        
    if "machine learning" in text or "ai" in text or "prediction" in text or "nlp" in text or "ocr" in text or "computer vision" in text:
        backend = "Python (FastAPI / Flask)"
        extra.append("TensorFlow / PyTorch / OpenCV (for AI/ML/CV)")
        
    if "blockchain" in text or "crypto" in text or "ledger" in text:
        extra.append("Ethereum / Polygon (Solidity), IPFS")
        
    if "real-time" in text or "live" in text or "tracking" in text:
        extra.append("WebSockets / Socket.io / Redis")
        
    if "geospatial" in text or "gis" in text or "map" in text:
        database = "PostgreSQL with PostGIS"
        extra.append("Mapbox / Leaflet / Google Maps API")
        
    if "iot" in text or "sensor" in text:
        extra.append("MQTT / AWS IoT / Node-RED")
        
    stack = [
        f"**Frontend/Mobile**: {frontend}",
        f"**Backend**: {backend}",
        f"**Database**: {database}"
    ]
    if extra:
        stack.append(f"**Specialized/Extra**: {', '.join(extra)}")
        
    return "\n".join("- " + s for s in stack)

with open('sih_software_ideas.md', 'w', encoding='utf-8') as f:
    f.write("# Smart India Hackathon (SIH) - Software Ideas\n\n")
    f.write("This document contains all Software category problem statements mapped to the requested themes, along with suggested tech stacks.\n\n")
    
    for theme in themes_to_extract:
        ideas = grouped[theme]
        # Title case theme name for header
        f.write(f"## Theme: {theme.title()}\n\n")
        
        if not ideas:
            f.write("*No software problem statements found for this theme.*\n\n")
            continue
            
        for idx, idea in enumerate(ideas, 1):
            title = idea.get('Problem Statement Title', 'No Title')
            org = idea.get('Organization', 'Unknown')
            desc = idea.get('Description', 'No Description')
            
            f.write(f"### {idx}. {title}\n")
            f.write(f"- **Organization**: {org}\n")
            f.write(f"- **Description**: {desc}\n")
            
            f.write("\n#### Suggested Tech Stack\n")
            f.write(suggest_tech_stack(title, desc) + "\n\n")
            f.write("---\n\n")

print(f"Extraction complete. Found software ideas:")
for t in themes_to_extract:
    print(f"- {t}: {len(grouped[t])}")
