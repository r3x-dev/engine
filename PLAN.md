Da się to zrobić bez porzucania `api_only`.

**Co Już Jest**
- `config/application.rb` już działa jako `api_only`, ale masz też `action_view/railtie`, więc HTML views są możliwe.
- `Gemfile` ma już `mission_control-jobs` i `propshaft`, a `Dockerfile` już robi `assets:precompile`.
- `config/routes.rb` dziś mountuje `MissionControl::Jobs::Engine` pod `/jobs` i root tam redirectuje.
- Sam `mission_control-jobs` pokazuje dokładnie wzorzec dla `api_only`: własny kontroler z modułami `ActionController::Base` i assety przez Propshaft/importmap.
- Dane do panelu już są:
  - katalog workflowów: `R3x::Workflow::Registry`
  - historia jobów: `solid_queue_jobs` + `solid_queue_*_executions`
  - stan triggerów: `trigger_states`
  - schedulowane taski: `solid_queue_recurring_tasks`

**Rekomendacja**
- Nie robiłbym osobnego engine na start.
- Zrobiłbym własny, server-rendered panel jako główny UI.
- `Mission Control` przeniósłbym na drugi plan, np. pod `/ops/jobs`.
- Root `/` ustawiałbym na customowy panel workflowów.
- Zostałbym przy plain Rails views + Propshaft + mały Stimulus tylko do theme toggle. Bez Reacta, bez nowego bundlera.

**Jak Bym To Ułożył**
1. `GET /` oraz `GET /workflows`
Lista workflowów.
Każdy wiersz/karta: `workflow_key.titleize`, klasa, badge triggerów, następny cron, ostatnie odpalenie, ostatni błąd, link do szczegółów.

2. `GET /workflows/:workflow_key`
Szczegóły jednego workflowu.
Sekcje: overview, triggery, stan change-detection, ostatnie odpalenia, link do surowego joba w Mission Control.

3. `GET /workflow-runs`
Historia wszystkich odpaleń workflowów.
Filtry: workflow, status, zakres czasu.

4. `GET /ops/jobs`
Mission Control zostaje jako niski poziom operacyjny: retry, discard, raw queue/job inspection.

**Proponowany Klimat UI**
- Bardziej “operations console” niż generyczny admin.
- Gęsta lista z czytelnymi status pillami.
- Jasny/ciemny motyw przez CSS variables.
- Domyślnie `prefers-color-scheme`, ręczny override zapisywany w `localStorage`.

Przykładowy kierunek:

```text
[ Workflows ] [ All Runs ] [ Infra Jobs ]                    [ Light/Dark ]

Workflows        Last Run         Next Trigger      Health
Daily Digest     Failed 5m ago    Today 13:00       Trigger error
Inbox Watch      Success 2m ago   Every 1 min       Healthy
Weekly Report    Scheduled        Mon 09:00         Healthy
```

**Technicznie**
1. Nowa namespace, np. `R3x::Dashboard`.
2. Własny `R3x::Dashboard::ApplicationController` oparty o wzorzec z Mission Control, żeby nie wyłączać `api_only`.
3. Własny layout + CSS + mały JS do motywu.
4. 1-2 małe query/presenter obiekty:
   - pobranie workflowów z `R3x::Workflow::Registry`
   - złożenie historii z `SolidQueue::Job` i execution tables
   - do triggerów: `R3x::TriggerState` i `SolidQueue::RecurringTask`
5. Panel zostawiłbym w v1 read-only, a akcje operacyjne delegował do Mission Control.
6. Dodałbym lazy `R3x::Workflow::Boot.load!` przed czytaniem `Registry`, żeby panel działał też stabilnie poza `bin/rails server`.
7. Testy:
   - request/integration tests dla routingu i renderu HTML
   - unit tests dla query/presenterów parsujących `solid_queue_jobs.arguments`
8. Trzeba też zaktualizować `AGENTS.md`, bo dziś opisuje `/jobs` jako root UI.

**Najważniejszy Tradeoff**
- MVP można zrobić bez nowej tabeli historii, wyłącznie na bazie `Solid Queue`.
- To jest szybkie i małe.
- Minus: pełna historia jest związana z `class_name` joba, a nie stabilnym `workflow_key`; po rename workflowu stare wpisy będą mniej eleganckie.
- Minus 2: dla zakończonych jobów nie masz idealnego, trwałego `started_at` i dokładnego runtime audit trail.
- Jeśli chcesz naprawdę mocną historię odpaleń, duration, stabilność po rename i lepsze filtrowanie, to warto od razu dodać osobne `workflow_runs`.

**Moja Sugestia**
- V1: bez nowej tabeli, root = custom panel, `Mission Control` pod `/ops/jobs`, panel read-only.
- V2: jeśli panel okaże się ważny operacyjnie, dodać `workflow_runs` i ewentualnie `Run now`.

**Do Potwierdzenia**
1. Czy `Mission Control` pod `/ops/jobs` Ci pasuje?
2. Historię robimy jako MVP z obecnych tabel, czy od razu pełny `workflow_runs` audit?
3. W v1 panel ma być tylko do podglądu, czy chcesz od razu przycisk `Run now` dla workflowów z manual triggerem?
