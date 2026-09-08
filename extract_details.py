from bs4 import BeautifulSoup

with open('sih_tables.html', 'r', encoding='utf-8') as f:
    soup = BeautifulSoup(f.read(), 'html.parser')

tables = soup.find_all('table')
ids_to_find = ['26129', '26155', '26002', '26103', '26018']

for table in tables:
    ps = {}
    for tr in table.find_all('tr'):
        cells = tr.find_all(['th', 'td'])
        if len(cells) == 2:
            key = cells[0].get_text(strip=True).replace(':', '')
            val = cells[1].get_text(strip=True)
            ps[key] = val
            
    ps_id = ps.get('Problem Statement ID')
    if ps_id in ids_to_find:
        print(f"ID: {ps_id}")
        print(f"Title: {ps.get('Problem Statement Title')}")
        desc = ps.get('Description', '')
        print(f"Desc: {desc[:300]}...")
        print("-" * 40)
        ids_to_find.remove(ps_id)
