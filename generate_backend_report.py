import json
import os
from bs4 import BeautifulSoup

artifact_dir = r"C:\Users\Himanshu\.gemini\antigravity-ide\brain\bd2a27bc-6dce-4299-bf82-8dc335d73af2"
report_path = os.path.join(artifact_dir, "sih_backend_recommendations.md")

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

# Adjusted weights heavily favoring Backend, API, Architecture, Data
keywords = {
    'backend': 10,
    'api': 8,
    'database': 8,
    'infrastructure': 7,
    'architecture': 7,
    'system': 6,
    'postgresql': 8,
    'temporal': 8,
    'orchestration': 8,
    'microservices': 8,
    'scale': 6,
    'data pipeline': 6,
    'integration': 5,
    'server': 5,
    'automation': 4,
    'ai': 2,
    'ml': 2
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
# Get top 20 to provide 10 more
top_20 = sorted_ps[:20]

md_content = "# Top 20 SIH Recommendations (Strong Backend Focus)\n\n"
md_content += "> [!NOTE]\n> Here are 20 problem statements ranked heavily towards **Backend, API, Database, Systems Architecture, and Orchestration**. The first 10 may overlap with the previous list if they had strong backend requirements, but this gives you 10 fresh, highly backend-intensive ideas.\n\n"

for i, ps in enumerate(top_20, 1):
    md_content += f"## {i}. {ps.get('Problem Statement Title', 'No Title')} (ID: {ps.get('Problem Statement ID', 'N/A')})\n\n"
    md_content += f"- **Organization**: {ps.get('Organization', 'N/A')} | **Department**: {ps.get('Department', 'N/A')}\n"
    md_content += f"- **Theme**: {ps.get('Theme', 'N/A')}\n"
    md_content += f"- **Backend Score**: {ps.get('score', 0)}\n\n"
    
    desc = ps.get('Description', 'No Description provided.')
    if len(desc) > 800:
        desc = desc[:800] + "..."
        
    md_content += f"**Description Extract**:\n> {desc}\n\n"
    md_content += "---\n\n"

with open(report_path, 'w', encoding='utf-8') as f:
    f.write(md_content)

print(f"Report generated at {report_path}")
