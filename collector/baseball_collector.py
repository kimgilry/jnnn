import json, re, os, sys, datetime, urllib.request, urllib.parse
from html import unescape

KST = datetime.timezone(datetime.timedelta(hours=9))
NOW = datetime.datetime.now(KST)
TODAY = NOW.date()

HEADERS = {
    "User-Agent": "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 Chrome/140 Safari/537.36",
    "Accept-Language": "ko-KR,ko;q=0.9,en;q=0.8",
    "Accept": "text/html,application/xhtml+xml,application/json;q=0.9,*/*;q=0.8",
}

def get(url, timeout=15):
    req = urllib.request.Request(url, headers=HEADERS)
    with urllib.request.urlopen(req, timeout=timeout) as r:
        return r.read().decode("utf-8", "ignore")

def get_json(url):
    return json.loads(get(url))

def kst_time(iso):
    try:
        dt=datetime.datetime.fromisoformat(iso.replace("Z","+00:00")).astimezone(KST)
        return dt.strftime("%H:%M"), dt.isoformat()
    except:
        return "", iso

def clean_html(x):
    x=re.sub(r"<script.*?</script>"," ",x,flags=re.S|re.I)
    x=re.sub(r"<style.*?</style>"," ",x,flags=re.S|re.I)
    x=re.sub(r"<[^>]+>"," ",x)
    return re.sub(r"\s+"," ",unescape(x)).strip()

def record_pct(w,l):
    try:
        w=int(w); l=int(l)
        return round(w/(w+l),4) if w+l else .5
    except: return .5

def mlb():
    games=[]
    date=TODAY.strftime("%Y-%m-%d")
    url=f"https://statsapi.mlb.com/api/v1/schedule?sportId=1&date={date}&hydrate=probablePitcher,team"
    data=get_json(url)
    for d in data.get("dates",[]):
        for g in d.get("games",[]):
            status=(g.get("status") or {}).get("abstractGameState","")
            detailed=(g.get("status") or {}).get("detailedState","")
            t, iso=kst_time(g.get("gameDate",""))
            away=(g.get("teams") or {}).get("away",{})
            home=(g.get("teams") or {}).get("home",{})
            ap=(away.get("probablePitcher") or {}).get("fullName","")
            hp=(home.get("probablePitcher") or {}).get("fullName","")
            games.append({
                "source":"MLB StatsAPI",
                "league":"MLB",
                "gamePk":str(g.get("gamePk","")),
                "timeKST":t,
                "startISO":iso,
                "status": "경기전" if status=="Preview" else ("종료" if status=="Final" else "경기중"),
                "statusDetail":detailed,
                "away":(away.get("team") or {}).get("name",""),
                "home":(home.get("team") or {}).get("name",""),
                "awayWins":away.get("leagueRecord",{}).get("wins"),
                "awayLosses":away.get("leagueRecord",{}).get("losses"),
                "homeWins":home.get("leagueRecord",{}).get("wins"),
                "homeLosses":home.get("leagueRecord",{}).get("losses"),
                "awayWinPct":record_pct(away.get("leagueRecord",{}).get("wins",0),away.get("leagueRecord",{}).get("losses",0)),
                "homeWinPct":record_pct(home.get("leagueRecord",{}).get("wins",0),home.get("leagueRecord",{}).get("losses",0)),
                "awayStarter":ap,
                "homeStarter":hp,
            })
    return games

def kbo_official():
    # Official English scoreboard. Parsing is intentionally conservative.
    games=[]
    ds=TODAY.strftime("%Y%m%d")
    urls=[
        f"https://eng.koreabaseball.com/Schedule/Scoreboard.aspx?gameDate={ds}",
        "https://eng.koreabaseball.com/Schedule/Scoreboard.aspx",
    ]
    html=""
    for u in urls:
        try:
            html=get(u)
            if len(html)>1000: break
        except: pass
    if not html: return games

    # Extract visible text around HH:MM / VS blocks. Unknown layouts are not guessed.
    text=clean_html(html)
    teams=["LG","HANWHA","KIA","SAMSUNG","LOTTE","DOOSAN","KT","SSG","NC","KIWOOM"]
    aliases={"HANWHA":"Hanwha","SAMSUNG":"Samsung","LOTTE":"Lotte","DOOSAN":"Doosan","KIWOOM":"Kiwoom"}
    # Generic pair finder around time.
    pat=re.compile(r"(\d{1,2}:\d{2}).{0,100}?("+"|".join(teams)+r").{0,80}?("+"|".join(teams)+r")",re.I)
    seen=set()
    for m in pat.finditer(text):
        a,b=m.group(2).upper(),m.group(3).upper()
        if a==b: continue
        key=m.group(1)+"|"+a+"|"+b
        if key in seen: continue
        seen.add(key)
        games.append({
            "source":"KBO Official",
            "league":"KBO","gamePk":key,
            "timeKST":m.group(1),"startISO":"",
            "status":"경기전",
            "away":aliases.get(a,a),"home":aliases.get(b,b),
            "awayWins":None,"awayLosses":None,"homeWins":None,"homeLosses":None,
            "awayWinPct":.5,"homeWinPct":.5,
            "awayStarter":"","homeStarter":""
        })
    return games

def npb_official():
    # Official NPB schedule page; conservative text parser.
    games=[]
    urls=[
        "https://npb.jp/games/",
        "https://npb.jp/bis/eng/2026/games/"
    ]
    html=""
    for u in urls:
        try:
            html=get(u)
            if len(html)>1000: break
        except: pass
    if not html: return games
    text=clean_html(html)
    names=["SoftBank","Hawks","Hanshin","Tigers","Giants","Yomiuri","BayStars","DeNA","Carp",
           "Yakult","Swallows","Dragons","Chunichi","Buffaloes","Orix","Fighters","Nippon-Ham",
           "Marines","Lotte","Eagles","Rakuten","Lions","Seibu"]
    pat=re.compile(r"(\d{1,2}:\d{2}).{0,100}?("+"|".join(map(re.escape,names))+r").{0,80}?("+"|".join(map(re.escape,names))+r")",re.I)
    seen=set()
    for m in pat.finditer(text):
        a,b=m.group(2),m.group(3)
        if a.lower()==b.lower(): continue
        key=m.group(1)+"|"+a+"|"+b
        if key in seen: continue
        seen.add(key)
        games.append({
            "source":"NPB Official",
            "league":"NPB","gamePk":key,"timeKST":m.group(1),"startISO":"",
            "status":"경기전","away":a,"home":b,
            "awayWins":None,"awayLosses":None,"homeWins":None,"homeLosses":None,
            "awayWinPct":.5,"homeWinPct":.5,"awayStarter":"","homeStarter":""
        })
    return games

def livescore_backup():
    # Optional backup only. 403 is expected on some networks and is not fatal.
    try:
        html=get("https://livescore.co.kr/sports/score_board/baseball_score.php")
        return {"ok":True,"bytes":len(html)}
    except Exception as e:
        return {"ok":False,"error":type(e).__name__+": "+str(e)[:120]}

def main():
    result={
        "generatedAt":NOW.isoformat(),
        "dateKST":TODAY.isoformat(),
        "mode":"PRE_GAME_ONLY",
        "oddsUsedForAnalysis":False,
        "sources":{},
        "games":[]
    }
    collectors=[("MLB",mlb),("KBO",kbo_official),("NPB",npb_official)]
    for name,fn in collectors:
        try:
            x=fn()
            result["games"].extend(x)
            result["sources"][name]={"ok":True,"games":len(x)}
        except Exception as e:
            result["sources"][name]={"ok":False,"error":type(e).__name__+": "+str(e)[:160]}
    result["sources"]["LivescoreBackup"]=livescore_backup()

    # Never invent games. Empty league stays empty and app will PASS.
    os.makedirs("live",exist_ok=True)
    with open("live/baseball.json","w",encoding="utf-8") as f:
        json.dump(result,f,ensure_ascii=False,indent=2)
    print(json.dumps(result["sources"],ensure_ascii=False))

if __name__=="__main__":
    main()
