import requests
import json
import re

url = "https://sih.gov.in/sih2026PS"
headers = {'User-Agent': 'Mozilla/5.0'}
response = requests.get(url, headers=headers)

if response.status_code == 200:
    html = response.text
    # Look for data tables JSON or JS arrays
    data = re.search(r'data:\s*(\[\{.*?\}\])', html, re.DOTALL)
    if data:
        with open('sih_data.json', 'w', encoding='utf-8') as f:
            f.write(data.group(1))
        print("Data saved to sih_data.json")
    else:
        # Fallback: find all tables
        from bs4 import BeautifulSoup
        soup = BeautifulSoup(html, 'html.parser')
        tables = soup.find_all('table')
        print(f"Found {len(tables)} tables.")
        if len(tables) > 0:
            with open('sih_tables.html', 'w', encoding='utf-8') as f:
                for table in tables:
                    f.write(str(table))
        else:
            print("No tables found. Saving raw HTML.")
            with open('sih_raw.html', 'w', encoding='utf-8') as f:
                f.write(html)
else:
    print(f"Failed to fetch. Status code: {response.status_code}")
