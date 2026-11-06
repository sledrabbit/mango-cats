package main

import (
	"database/sql"
	"fmt"
	"html/template"
	"log"
	"net/http"
	"os"
	"time"

	_ "modernc.org/sqlite"
)

const maxFeedings = 10

var page = template.Must(template.New("page").Parse(`<!doctype html>
<html lang="en">
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Mango Cats</title>
<style>
  * { box-sizing: border-box; }
  body { font-family: ui-monospace, SFMono-Regular, Menlo, Consolas, monospace; min-height: 100vh; margin: 0; padding: 1.5rem; display: grid; place-items: center; background: #f5f0df; color: #253b2f; }
  .calendar { width: min(100%, 28rem); text-align: center; background: #fffdf3; border: 2px solid currentColor; box-shadow: 8px 8px 0 #253b2f; }
  header { padding: 1rem; border-bottom: 2px dashed currentColor; background: #e5edce; }
  header span { display: block; font-weight: 700; letter-spacing: .12em; text-transform: uppercase; }
  header strong { display: block; font-size: 3.5rem; line-height: 1.1; }
  main { padding: 1.5rem; }
  .cat { margin: 0 auto 1.5rem; font: inherit; font-size: 1.4rem; line-height: 1.05; }
  h1 { margin: 0 0 1.5rem; font-size: 1.3rem; }
  .count { display: inline-block; min-width: 5rem; padding: .25rem 1rem; border: 2px solid currentColor; font-size: 4rem; line-height: 1.2; }
  p { margin: 1rem 0; }
  form { margin-top: 1.5rem; }
  button { padding: .75rem 1rem; border: 2px solid currentColor; background: #e5edce; color: inherit; font: inherit; font-weight: 700; box-shadow: 3px 3px 0 currentColor; cursor: pointer; }
  button:hover { background: #d3e3b5; }
  button:focus-visible { outline: 2px dashed currentColor; outline-offset: 6px; }
  .joke { padding: .75rem; border: 2px dashed currentColor; font-weight: 700; }
  small { display: block; margin-top: 2rem; }
</style>
<div class="calendar">
  <header><span>-- {{.Month}} --</span><strong>{{.Date}}</strong><span>{{.Weekday}}</span></header>
  <main>
    <pre class="cat" aria-label="ASCII art cat"> /\_/\
( o.o )
 &gt; ^ &lt;</pre>
    <h1>Has anyone fed the cat?</h1>
    <strong class="count">{{.Count}}</strong>
    <p>feedings today / {{.Max}} max</p>
    {{if ge .Count .Max}}
      <p class="joke">your cat is now mango shaped</p>
    {{else}}
      <form method="post" action="/feed"><button>[ + ] I fed the cat</button></form>
    {{end}}
    <small>Resets at midnight, Pacific time.</small>
  </main>
</div>
</html>`))

func main() {
	zone, err := time.LoadLocation("America/Los_Angeles")
	if err != nil {
		log.Fatal(err)
	}
	path := os.Getenv("DB_PATH")
	if path == "" {
		path = "cats.db"
	}
	db, err := sql.Open("sqlite", path)
	if err != nil {
		log.Fatal(err)
	}
	defer db.Close()
	db.SetMaxOpenConns(1)
	if _, err := db.Exec("CREATE TABLE IF NOT EXISTS feedings (fed_at INTEGER NOT NULL)"); err != nil {
		log.Fatal(err)
	}

	mux := http.NewServeMux()
	mux.HandleFunc("GET /{$}", func(w http.ResponseWriter, r *http.Request) {
		now := time.Now().In(zone)
		start, end := dayBounds(now, zone)
		var count int
		if err := db.QueryRowContext(r.Context(), "SELECT COUNT(*) FROM feedings WHERE fed_at >= ? AND fed_at < ?", start, end).Scan(&count); err != nil {
			http.Error(w, "database error", http.StatusInternalServerError)
			return
		}
		w.Header().Set("Content-Type", "text/html; charset=utf-8")
		w.Header().Set("Cache-Control", "no-store")
		if err := page.Execute(w, struct {
			Month   string
			Date    string
			Weekday string
			Count   int
			Max     int
		}{now.Format("January"), now.Format("2"), now.Format("Monday"), count, maxFeedings}); err != nil {
			log.Print(err)
		}
	})
	mux.HandleFunc("POST /feed", func(w http.ResponseWriter, r *http.Request) {
		now := time.Now().In(zone)
		start, end := dayBounds(now, zone)
		_, err := db.ExecContext(r.Context(), `INSERT INTO feedings (fed_at)
			SELECT ? WHERE (SELECT COUNT(*) FROM feedings WHERE fed_at >= ? AND fed_at < ?) < ?`,
			now.Unix(), start, end, maxFeedings)
		if err != nil {
			http.Error(w, "database error", http.StatusInternalServerError)
			return
		}
		http.Redirect(w, r, "/", http.StatusSeeOther)
	})
	mux.HandleFunc("GET /health", func(w http.ResponseWriter, r *http.Request) {
		var count int
		if err := db.QueryRowContext(r.Context(), "SELECT COUNT(*) FROM feedings").Scan(&count); err != nil {
			http.Error(w, "database unavailable", http.StatusServiceUnavailable)
			return
		}
		fmt.Fprintln(w, "ok: app and database")
	})

	log.Println("listening on :8080")
	log.Fatal((&http.Server{Addr: ":8080", Handler: mux, ReadHeaderTimeout: 5 * time.Second}).ListenAndServe())
}

func dayBounds(now time.Time, zone *time.Location) (int64, int64) {
	start := time.Date(now.Year(), now.Month(), now.Day(), 0, 0, 0, 0, zone)
	return start.Unix(), start.AddDate(0, 0, 1).Unix()
}
