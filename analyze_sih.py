import json
from bs4 import BeautifulSoup
import re

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

# Keywords indicating fit for the user's mastery
keywords = [
    'ai', 'ml', 'artificial intelligence', 'machine learning',
    'ocr', 'computer vision', 'automation', 'backend', 'api',
    'workflow', 'document', 'text extraction', 'image processing',
    'intelligent', 'prediction', 'analytics'
]

scored_ps = []
for ps in problem_statements:
    if ps.get('Category', '') != 'Software':
        continue
    
    text_to_search = (ps.get('Problem Statement Title', '') + ' ' + ps.get('Description', '')).lower()
    score = 0
    for kw in keywords:
        if kw in text_to_search:
            # weigh some keywords more
            if kw in ['ocr', 'computer vision']:
                score += 3
            elif kw in ['ai', 'ml', 'machine learning', 'automation']:
                score += 2
            else:
                score += 1
                
    if score > 0:
        ps['score'] = score
        scored_ps.append(ps)

# Sort by score descending
scored_ps.sort(key=lambda x: x['score'], reverse=True)

# Select top 20 to review (to pick top 10 unique ones)
top_ps = scored_ps[:20]

with open('sih_top.json', 'w', encoding='utf-8') as f:
    json.dump(top_ps, f, indent=4)

print(f"Parsed {len(problem_statements)} total PS. Filtered down to {len(scored_ps)} relevant Software PS.")
print("Saved top 20 to sih_top.json")
