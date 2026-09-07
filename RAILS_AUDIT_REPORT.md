# R3x — analiza utrzymania i wykorzystania nowych funkcji

Data: 2026-09-05. Analizowany HEAD: `418719c`.

Największy zwrot dadzą poprawki odporności na ponowienia, uproszczenie integracji z Solid Queue oraz wykorzystanie obserwowalności RubyLLM. Fundament jest już nowoczesny; nie ma uzasadnienia dla przepisywania silnika ani dokładania ogólnego frameworka orkiestracji.

## Zakres i pewność

Przegląd statyczny runtime, integracji, dashboardu, schematu bazy, konfiguracji i odpowiednich testów, uzupełniony dokumentacją upstream oraz kodem zainstalowanych gemów. Wybrane workflowy z osobnego repo `workflows/` służyły do sprawdzenia realnego użycia. Stan obu checkoutów był czysty przed analizą.

Nie uruchamiano workflowów, zapytań do usług produkcyjnych, pełnego CI, SimpleCov ani RubyCritic. Nie zmieniono kodu aplikacji. Nie przedstawiam procentowego pokrycia, benchmarków ani stanu produkcji jako zmierzonych. Opisane scenariusze błędów wynikają z kodu; regresje trzeba potwierdzić testem podczas wdrażania poprawek. Przegląd bezpieczeństwa nie zastępuje bieżącego Brakeman/bundler-audit.

## Wersje i dawne ograniczenia

| Element | W checkoutcie | Wniosek |
|---|---|---|
| Ruby | 4.0.6 | Brak potrzeby migracji języka dla poniższych propozycji. |
| Rails | 8.1.3.1 | `ActiveJob::Continuable` i lokalne `bin/ci` są już używane. |
| Solid Queue | 1.7.0 | Dostępne batches, tryb fibers i natywny wybór samego schedulera. |
| RubyLLM | 1.16.0 | Dostępne zdarzenia instrumentacji i obliczanie kosztów odpowiedzi. |
| Schematist | 1.1.0 | Migracja aplikacyjnego DSL schematów jest już wykonana. |
| HTTPX | 1.8.3 | Warto zachować sprawdzone obejście uploadu StringIO. |
| Flightdeck | 1.2.0 | Pozostawić mu operacje administracyjne kolejki. |

Źródło wersji: `.ruby-version`, `Gemfile.lock:251`, `Gemfile.lock:344`, `Gemfile.lock:435–478`. Strony wydań [RubyLLM](https://github.com/crmne/ruby_llm/releases) i [Solid Queue](https://github.com/rails/solid_queue/releases) wskazują odpowiednio 1.16.0 i 1.7.0 jako najnowsze stabilne wydania w momencie sprawdzania. Nie wykonano pełnego `bundle outdated` dla wszystkich zależności.

**Dawna blokada schematów nadal jest widoczna w zależnościach:** RubyLLM 1.16.0 wymaga `ruby_llm-schema (~> 0)`, więc wersja 0.4.0 pozostaje tranzytywnie w lockfile. Aplikacja korzysta bezpośrednio ze Schematist przez mały `LlmSchema.define`. Nie usuwałbym wrappera ani nie wymuszał aktualizacji zależności tranzytywnej. To sensownie rozwiązana wcześniejsza blokada, a nie zapomniana migracja. [Gemspec RubyLLM 1.16.0](https://raw.githubusercontent.com/crmne/ruby_llm/1.16.0/ruby_llm.gemspec).

Uwaga dotycząca dokumentacji: wynik Context7 dla gałęzi `main` opisuje już `Message#parsed`. Zainstalowane 1.16.0 nadal parsuje structured output do `content` i nie definiuje `parsed`. Nie należy mechanicznie zmieniać obecnych wywołań `.content` na podstawie dokumentacji rozwojowej. Zweryfikowano w lokalnych `ruby_llm-1.16.0/lib/ruby_llm/message.rb` i `chat.rb` oraz [kodzie tagu 1.16.0](https://raw.githubusercontent.com/crmne/ruby_llm/1.16.0/lib/ruby_llm/chat.rb).

## Poprawność i integracje

### R1 — wysoki: utrwalić wynik digestu i rozdzielić dostawy

Dowód: `workflows/madeira_weekly_news_digest/workflow.rb:44–75`; istniejący wpis `docs/todo.md:11`.

Kolejność to wygenerowanie digestu → Gmail → Feedway → potwierdzenie Miniflux. Awaria po Gmailu zostawia workflow bez potwierdzonego końca. Ponowne uruchomienie, np. ręczny retry po błędzie Feedway, może ponownie wygenerować treść i wysłać mail. Obecne `retry_on` dotyczy błędów LLM, więc nie twierdzę, że błąd Feedway automatycznie uruchamia retry.

Propozycja: jeden stabilny zestaw wejściowy i wynik dla konkretnego wydania digestu, osobne etapy dostawy i potwierdzenia. Najpierw wykorzystać istniejące Continuable. Cache TTL może ograniczyć koszt ponownej generacji, ale nie zastępuje trwałego wyniku, jeśli utrata treści jest niedopuszczalna. Nie używać samego przedziału TTL jako tożsamości wydania, jeżeli retry może przekroczyć jego granicę.

Ograniczenie: `step` nie zapewnia dokładnie jednej dostawy, jeśli proces umrze po zaakceptowaniu maila przez dostawcę, a przed zapisem postępu. Wymóg twardej deduplikacji oznacza osobny projekt potwierdzeń/idempotencji dostaw. Wdrożenie w repo workflowów, z ręcznym sprawdzeniem zgodnym z jego zasadami.

### R2 — średni: klient Miniflux powinien sam respektować dry-run dla zapisów

Dowód: `app/lib/r3x/client/miniflux.rb:40–57`, `:68–71`.

`update_entries` i `mark_category_entries_as_read` zawsze wykonują PUT. Bezpośrednie użycie klienta przez nowy workflow lub scratchpad omija `R3X_DRY_RUN`. Aktualny digest ma własną ochronę w `workflow.rb:290–294`, więc nie jest to dowód, że jego zwykły dry-run dzisiaj zmienia Miniflux.

Propozycja: umieścić ochronę przy mutujących metodach klienta przez istniejące `R3x::Policy.dry_run_for(:miniflux)`, zachować rzeczywiste odczyty. Przy implementacji uzgodnić zachowanie potwierdzeń workflowu z niezależnymi ustawieniami Gmail/Feedway/Miniflux.

Akceptacja: WebMock potwierdza brak PUT w dry-run i poprawne żądanie przy jawnej rzeczywistej operacji.

### R3 — średni: kolizje nagłówków Google Sheets mogą gubić kolumny

Dowód: `app/lib/r3x/client/google_sheets.rb:38–48`; istniejący test sprawdza jedynie prosty duplikat `Name, Name, Email`.

Nagłówki `Name, Name, Name_2` są zamieniane na `Name, Name_2, Name_2`. Końcowe `to_h` nadpisuje jedną wartość. To deterministyczna kolizja w algorytmie nadawania nazw.

Propozycja: wybierać nazwy unikalne w całym zbiorze wynikowym, z jawną polityką zachowania istniejących nazw z sufiksami. Alternatywnie odrzucać kolizyjny schemat, jeśli automatyczne przemianowanie jest niepożądane.

Akceptacja: regresje dla istniejących sufiksów i powtórzonych/pustych nagłówków; żadna kolumna nie znika.

### R4 — średni: domyślne retry LLM powinno być krótkie

Dowód: `app/lib/r3x/client/llm.rb:8–10`, `:56–58`. Domyślna konfiguracja pozwala na trzy ponowienia z bazowymi opóźnieniami 60, 120, 240 sekund; dochodzi czas żądań i ewentualny jitter.

Aktywne przejrzane workflowy już przekazują `max_retries: 0` i używają `retry_on`. Problem dotyczy ergonomii nowych wywołań: domyślne ustawienia klienta kierują autora w stronę wielominutowego zajmowania workera, wbrew zasadom projektu.

Propozycja: krótki domyślny retry HTTP albo zero oraz jawne, ograniczone `retry_on` w workflowach. Nie dodawać globalnego retry wszystkich błędów i nie powielać polityki na dwóch poziomach. Zmiana defaultu wymaga sprawdzenia wywołań, które obecnie na nim polegają.

### R5 — wysoki: nie maskować błędów SQL jako braku tabel lub danych

Dowód: `lib/r3x/workflow/boot.rb:20–23` przechwytuje każde `ActiveRecord::StatementInvalid` i kontynuuje po komunikacie „tables not available”. Błąd uprawnień, niezgodny schemat albo wadliwe zapytanie podczas synchronizacji harmonogramów może więc zostać potraktowane jak oczekiwany bootstrap. Proces może przejść dalej z niezsynchronizowanymi zadaniami; nie oznacza to automatycznie, że wszystkie istniejące zadania znikną.

Podobny problem występuje w dashboardzie: `app/lib/r3x/dashboard/workflow/catalog.rb:56–60`, `runs.rb:77–109` i `summaries.rb:213–217` zamieniają błędy zapytań w puste kolekcje.

Propozycja: rozdzielić świadomie obsługiwany brak przygotowanej bazy od rzeczywistej awarii SQL. Synchronizacja katalogu w normalnym boot powinna kończyć się błędem przy niepowodzeniu. Dashboard powinien sygnalizować niedostępność danych i logować przyczynę. Błąd DB nie powinien wyglądać jak poprawny pusty katalog.

Akceptacja: regresje rozróżniające świeżą instalację i błąd zapytania, bez wykonywania migracji w samym mechanizmie obsługi wyjątku.

### R6 — wysoki: stabilny zestaw eventów i oddzielenie claim od „przetworzone”

Dowód: `workflows/camara_ps_events/workflow.rb:28–39`, `:76–78`, `:121–123`.

Kroki `process_event_0`, `process_event_1` odnoszą się do pozycji w liście pobieranej przez okresowy cache. Wznowienie po zmianie przedziału cache lub jego usunięciu może zobaczyć inną listę, ale stare nazwy ukończonych kroków. Wtedy można pominąć event, który teraz zajmuje pozycję wcześniej obsłużonego. Najpierw utrwalić zestaw wejściowy konkretnego przebiegu i jego kolejność. Sama zamiana indeksu na ID nie rozwiązuje całego kontraktu kolejności kroków Continuable.

Drugi problem: `processed_events.add?` jest jednocześnie claimem przed pracą i markerem zakończenia. Wyjątek Ruby usuwa wpis w rescue, ale twardo ubity proces tego nie zrobi. Kolejne uruchomienie potraktuje niedokończony event jako przetworzony do czasu usunięcia/wygaszenia wpisu.

Propozycja: jeśli powiadomienia wymagają tej niezawodności, osobny krótki claim z określonym terminem ważności i osobny marker udanego zakończenia; dla twardych gwarancji mały rekord dostawy z unikalnym kluczem. Dobór czasu claimu i jego przejmowanie po awarii wymagają jawnego kontraktu. Dotyczy to też pomysłu z `docs/todo.md:13–14`: proste przeniesienie markera przed Discord zmienia ryzyko duplikatu w ryzyko utraty dostawy po awarii. Nie przedstawiać tego jako rozwiązania exactly-once.

### R7 — niski: odbudowa registry powinna zachować spójny stan po błędzie

Dowód: `lib/r3x/workflow/pack_loader.rb:20–48`. Po wcześniejszym sukcesie wymuszony rebuild czyści registry, lecz błąd w środku ładowania nie zeruje flagi `LOADED`. Kolejne zwykłe `load!` może zatem pominąć odbudowę częściowego katalogu.

Dotyczy głównie narzędzi wykonujących rebuild w tym samym procesie i przechwytujących wyjątek. Zwykły świeży boot kończy się błędem, więc nie klasyfikuję tego jako typowej awarii produkcyjnej. Najmniejsza poprawka to spójne resetowanie stanu przy porażce; pełna atomowa podmiana katalogu tylko jeśli naprawdę potrzeba zachować poprzedni katalog.

## Dashboard i baza danych

### D1 — średni: limitować logiczne przebiegi, nie ich fragmenty

Dowód: `app/lib/r3x/dashboard/workflow/runs.rb:20–25`, `:77–85`, `:127–131`.

Przy filtrach lista pobiera maksymalnie `limit * 10` fizycznych jobów, potem grupuje je w Ruby po `active_job_id`. Przy wielu wznowieniach kilku przebiegów może zapełnić całe okno 500 rekordów. UI pokaże mniej niż oczekiwane 50 logicznych przebiegów mimo dostępnej starszej historii. Bez filtrów okno jest jeszcze mniejsze: `limit`.

Propozycja: wybierać i ograniczać logiczne identyfikatory w SQL, a następnie dociągać fragmenty wybranych przebiegów. Zachować semantykę filtrów i sortowanie po rzeczywistej aktywności. To usuwa arbitralny mnożnik i upraszcza uzasadnianie kompletności listy. Akceptacja na SQLite i PostgreSQL: wiele wznowień jednego joba nie wypiera odrębnych przebiegów z listy.

### D2 — średni, zależny od skali: liczyć aktywność po stronie bazy

Dowód: `app/lib/r3x/dashboard/workflow/run_counts.rb:11–41`. Licznik wykonuje osiem zapytań i materializuje wszystkie pasujące joby przez `flat_map(&:to_a)`, aby policzyć unikalne logiczne przebiegi w Ruby.

Propozycja: wspólne SQL `UNION` i agregacja, zachowujące grupowanie po `active_job_id` oraz fallback dla pustego ID. W repo istnieje już `Dashboard::Run.logical_count`, więc wykorzystać obecny model zamiast dodawać osobny system raportowania. Brak benchmarku i wolumenu produkcyjnego: to potwierdzony mechanizm wzrostu kosztu, nie zmierzona dzisiaj wolna strona.

## Nowe możliwości i uproszczenia dostępne teraz

### N1 — duży potencjał: Solid Queue batches

Solid Queue 1.7 dodał grupy zadań z callbackami zakończenia. Pozwala to zbudować np. „przetwórz niezależne materiały, potem przygotuj wspólny wynik” przy użyciu istniejącej kolejki. [Wydanie 1.7.0](https://github.com/rails/solid_queue/releases/tag/v1.7.0).

Repo ma nowy gem, ale `db/schema.rb:52` nie zawiera `solid_queue_jobs.batch_id`, a migracje nie tworzą tabel batches. To **brak aktywacji nowej funkcji**, nie dowód awarii obecnych jobów: upstream celowo obsługuje stary schemat. Przed użyciem trzeba przenieść migrację upstream do używanej tu bazy primary, zweryfikować oba adaptery i zdecydować o czyszczeniu zakończonych grup. Generator domyślnie wskazuje bazę `queue`, więc nie kopiować bezmyślnie komendy z wielobazowego przykładu. [Instrukcja aktualizacji](https://github.com/rails/solid_queue/blob/v1.7.0/README.md#upgrading-existing-installations).

Rekomendacja: pojedynczy pilot dla rzeczywiście niezależnych prac. Sekwencyjne i celowo opóźniane kroki, np. monitoring kamer, mogą pozostać Continuable. Batches nie utrwalają automatycznie wyników biznesowych i nie eliminują problemów idempotencji. Integracja z własnym dashboardem wymaga świadomej prezentacji grupy i zadań pomocniczych.

Nie dodawać przy okazji globalnego `limits_concurrency`: ręczny enqueue przez `Dashboard::DirectWorkflowEnqueuer` buduje zastępczą klasę ActiveJob bez ładowania workflowu, więc nie przejmuje jego deklaracji współbieżności. Każda taka nowa polityka musi zachować zgodność między harmonogramem a ręcznym uruchomieniem.

### N2 — szybki zysk: instrumentacja i koszty RubyLLM

RubyLLM 1.16 oferuje `chat.ruby_llm` i `request.ruby_llm`; 1.15 dodał m.in. `response.cost.total`. W repo nie znalazłem subskrypcji tych zdarzeń ani wykorzystania kosztów. [Instrumentacja 1.16](https://github.com/crmne/ruby_llm/releases/tag/1.16.0), [koszty 1.15](https://github.com/crmne/ruby_llm/releases/tag/1.15.0).

Propozycja: rejestrować model, dostawcę, czas, tokeny i szacowany koszt z istniejącym `r3x.run_active_job_id`; wykorzystać już posiadane logi/VictoriaLogs. To pomoże wskazać, które fetches naprawdę warto cache'ować i gdzie potrzebna jest większa współbieżność.

Istotny szczegół: gem jest ładowany leniwie po boot, a automatyczne podłączenie instrumentera znajduje się w jego Railtie. Przy integracji jawnie skonfigurować `ActiveSupport::Notifications` w kontrolowanym punkcie ładowania i sprawdzić emisję zdarzenia. Sam subscriber może nie wystarczyć. Koszt jest estymacją na podstawie metadanych cen; brak ceny dla własnego providera nie powinien oznaczać zera. Ograniczyć zapis do metadanych, bez całych promptów i odpowiedzi.

### N3 — mały, konkretny refaktor: natywny tryb samego schedulera

`lib/r3x/workflow/entrypoint.rb:31–35` wybiera osobny `config/queue.scheduler.yml`. Solid Queue od 1.5.1 posiada `--only-recurring` / `SOLID_QUEUE_ONLY_RECURRING`. [Wydanie 1.5.1](https://github.com/rails/solid_queue/releases/tag/v1.5.1).

Propozycja: zachować `bin/jobs-scheduler` i jego jawne ładowanie/synchronizację workflowów, ale wybór procesów powierzyć opcji upstream. Można wtedy współdzielić konfigurację schedulera z `queue.yml`. Warunek: zachować `dynamic_tasks_enabled: true`, polling i świadomą obsługę istniejących override'ów. Dispatcher pozostaje potrzebny w procesie workerów.

### N4 — opcjonalnie, po pomiarze: workers na fibers

Solid Queue 1.6 dodał wykonywanie jobów na fibers. Wymaga gema Async oraz Rails isolation level `:fiber`; obecna konfiguracja używa threads. [Wydanie 1.6.0](https://github.com/rails/solid_queue/releases/tag/v1.6.0).

Może pomóc przy dużej liczbie równoległych oczekiwań na HTTP/LLM. Dla kilku workflowów z małym obciążeniem korzyść jest nieudowodniona, a rośnie powierzchnia konfiguracji. Najpierw instrumentacja, następnie ograniczony eksperyment z pomiarem przepustowości, pamięci i połączeń DB. Nie włączać globalnie wyłącznie dlatego, że funkcja jest dostępna.

## Utrzymanie UI i zależności

### U1 — średni: dekoracyjna zmiana Flightdeck nie powinna warunkować boot

Dowód: `config/initializers/flightdeck.rb:21–27`. Kod sprawdza obecność `flightdeck_brand_svg`, rzuca wyjątek przy zmianie upstream i nadpisuje metodę przez `module_eval` tylko po to, aby dodać link powrotny.

Propozycja: usunąć zależność boot od tej dekoracji. Najprościej zrezygnować z własnego brandingu i pozostawić zwykły link do Flightdeck we własnym UI; jeśli link zwrotny jest wymagany, zaproponować upstream publiczny punkt konfiguracji. Przejrzane API konfiguracyjne zainstalowanego 1.2.0 nie zawiera opcji dla takiego linku. Nie zamieniać wyjątku na kolejną warstwę monkey patchy.

### U2 — niski: zachować wyraźny podział własnego dashboardu i Flightdeck

Flightdeck ma już obsługę retry/discard, kolejek, procesów i recurring tasks. Własne UI ma sens dla workflowów, logicznych przebiegów i skorelowanych logów. Nie rozbudowywać dwóch paneli o te same operacje kolejki. [Możliwości Flightdeck](https://github.com/cmer/solid_queue-flightdeck).

Layout własnego dashboardu ma 1033 linie, w tym duże bloki CSS i JS (`app/views/layouts/r3x/dashboard.html.erb:10`, `:858`). Przy następnej większej zmianie UI warto wyodrębnić te bloki do czytelnych plików/partials. Nie ma potrzeby dodawania SPA ani nowego bundlera tylko z tego powodu.

### U3 — średni: przegląd minorów zależności powinien obejmować funkcje i migracje

`.github/renovate.json5:43–53` automatycznie scala minory. Przykład Solid Queue pokazuje, że nowy gem może przejść dotychczasowe testy, a nowa funkcja pozostać wyłączona z powodu braku migracji. Dla Solid Queue/RubyLLM/Flightdeck warto przy minorze przejrzeć changelog pod kątem migracji, używanych wewnętrznych API i nowych możliwości. Nie wymaga to ręcznego zatwierdzania każdego patcha ani rozszerzania CI o kosztowny audyt całego świata.

## Testy i rzeczy do zachowania

Minitest, WebMock, Mocha, prawdziwe rekordy Solid Queue oraz sprawdzanie SQLite i PostgreSQL to dobry fundament. Nie proponuję migracji do RSpec ani testowania prywatnych workflow packów w silniku.

Przy poprawkach najbardziej wartościowe będą testy kontraktów: brak efektu zewnętrznego w dry-run, kompletność danych po normalizacji, prawidłowe grupowanie prób joba i granice wznowienia. Nie ma podstaw do wymyślania procentowego celu coverage z samej liczby plików.

Zachować rozdział web/workers/scheduler, dashboard oparty na persisted artifacts, autoryzację należącą do deploymentu, małe klienty HTTPX i leniwe ładowanie ciężkich gemów. Nie zastępować `DurableSet` wszędzie tabelą: jego best-effort kontrakt jest jawny. Twarda unikalność powinna powstać tylko tam, gdzie wymaga jej konkretny efekt biznesowy.

Nie usuwać automatycznie obejścia Tempfile w `Http#upload_file`: kod HTTPX 1.8.3 w `Transcoder::Multipart::Part.call` nadal traktuje zwykłe StringIO inaczej niż obiekt z `path` i `read`. Ewentualne uproszczenie wymaga dowodu na rzeczywistych bajtach multipart, nazwie, MIME i zachowaniu wejściowego IO.

## Proponowana kolejność

1. Poprawki poprawności: jawne błędy synchronizacji harmonogramów, stabilne wznowienia Camara i digestu. Osobne małe zakresy; workflowy należą do osobnego repo.
2. Ochrona zapisów Miniflux, kolizje nagłówków Sheets i kompletność listy logicznych przebiegów.
3. Instrumentacja LLM, krótkie retry jako domyślny kontrakt klienta, natywny tryb schedulera i usunięcie zależności boot od dekoracji Flightdeck.
4. Przygotowanie schematu Solid Queue i pilot batches dla jednej uzasadnionej operacji.
5. Fibers i szersze zmiany UI dopiero na podstawie pomiarów lub konkretnej potrzeby produktu.

Rekomendacje są materiałem do wyboru i review. Ten raport nie zmienia `docs/todo.md` ani architektury i nie oznacza akceptacji całego backlogu do wdrożenia.
