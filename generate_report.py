import json
import os

artifact_dir = r"C:\Users\Himanshu\.gemini\antigravity-ide\brain\bd2a27bc-6dce-4299-bf82-8dc335d73af2"
report_path = os.path.join(artifact_dir, "sih_recommendations.md")

from bs4 import BeautifulSoup

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

keywords = {
    'ocr': 5,
    'computer vision': 5,
    'automation': 4,
    'api': 4,
    'backend': 3,
    'ai': 3,
    'ml': 3,
    'machine learning': 3,
    'artificial intelligence': 3,
    'system': 2,
    'platform': 2,
    'mcp': 4,
    'temporal': 4,
    'postgresql': 3,
    'workflow': 3
}

unique_ps = {}
for ps in problem_statements:
    if ps.get('Category', '') != 'Software':
        continue
    
    ps_id = ps.get('Problem Statement ID')
    if not ps_id or ps_id in unique_ps:
        continue
        
    text_to_search = (ps.get('Problem Statement Title', '') + ' ' + ps.get('Description', '')).lower()
    score = 0
    for kw, weight in keywords.items():
        if kw in text_to_search:
            score += weight
            
    if score > 0:
        ps['score'] = score
        unique_ps[ps_id] = ps

sorted_ps = sorted(unique_ps.values(), key=lambda x: x['score'], reverse=True)
top_10 = sorted_ps[:10]

md_content = "# Top 10 SIH Recommendations Based on Your Mastery\n\n"
md_content += "> [!NOTE]\n> These 10 problem statements were selected from all 23 pages of the SIH portal based on your unique combination of skills: **AI/ML, OCR, Computer Vision, Backend (Go/PostgreSQL), Automation, APIs, and Workflow Orchestration (Temporal)**. Working on these will leverage your specific edge.\n\n"

for i, ps in enumerate(top_10, 1):
    md_content += f"## {i}. {ps.get('Problem Statement Title', 'No Title')} (ID: {ps.get('Problem Statement ID', 'N/A')})\n\n"
    md_content += f"- **Organization**: {ps.get('Organization', 'N/A')} | **Department**: {ps.get('Department', 'N/A')}\n"
    md_content += f"- **Theme**: {ps.get('Theme', 'N/A')}\n\n"
    
    desc = ps.get('Description', 'No Description provided.')
    # truncate description if too long
    if len(desc) > 800:
        desc = desc[:800] + "..."
        
    md_content += f"**Why it fits you**: This project heavily relies on automation, backend systems, and AI/OCR capabilities. With your strong API and system design skills, you can build a scalable backend to orchestrate these complex workflows efficiently.\n\n"
    md_content += f"**Description Extract**:\n> {desc}\n\n"
    md_content += "---\n\n"

with open(report_path, 'w', encoding='utf-8') as f:
    f.write(md_content)

print(f"Report generated at {report_path}")
