import Toybox.Lang;
import Toybox.System;

// Tiny translation layer: Tr.s("Rounds") gives "Tours" on a watch set to
// French, the English text otherwise. English is the key, so a missing
// translation just shows English. Settings strings are in resources-fre/.
module Tr {

    var _fr as Dictionary<String, String>? = null;
    var _checked as Boolean = false;

    function isFrench() as Boolean {
        if (!_checked) {
            _checked = true;
            if (System.getDeviceSettings().systemLanguage == System.LANGUAGE_FRE) { _fr = french(); }
        }
        return _fr != null;
    }

    function s(en as String) as String {
        if (!isFrench()) { return en; }
        var t = (_fr as Dictionary<String, String>).get(en);
        return t == null ? en : t;
    }

    function french() as Dictionary<String, String> {
        return {
            // run screen
            "WORK" => "EFFORT", "GET READY" => "PRÊT", "REST" => "REPOS", "PAUSED" => "PAUSE",
            "DONE" => "FINI", "DONE, WAIT" => "FINI, ATTENDS", "Rounds" => "Tours", "Round" => "Tour",
            "Int" => "Int", "Reps" => "Reps", "HR" => "FC", "NEXT" => "SUIVANT",
            "BACK" => "RETOUR", "+1 round" => "+1 tour", "done" => "fait",
            "TASK" => "TÂCHE", "SET" => "SÉRIE", "Set" => "Série", "Rest" => "Repos",
            // quick timer
            "Quick timer" => "Timer rapide", "No WOD needed" => "Sans WOD", "Start timer" => "Démarrer",
            "Type" => "Type", "Duration" => "Durée", "Time cap" => "Time cap", "Every" => "Toutes les",
            "Intervals" => "Intervalles", "Work / rest" => "Effort / repos", "No cap" => "Sans cap",
            "rounds" => "tours", "For time" => "For time",
            "Last interval" => "Dernier intervalle", "Next" => "Suivant",
            "HALFWAY" => "MI-TEMPS", "1 MIN LEFT" => "1 MIN RESTANTE", "max" => "max",
            // menus
            "Today" => "Aujourd'hui", "My WODs" => "Mes WODs", "My stats" => "Mes stats",
            "Coach" => "Coach", "Sync WOD" => "Synchroniser", "Samples" => "Exemples",
            "Get started" => "Démarrer", "Settings WOD error" => "Erreur WOD réglages",
            "Synced" => "Synchro", "Never synced" => "Jamais synchronisé",
            "Set URL in settings" => "URL dans les réglages", "workouts" => "séances",
            "New weekly report" => "Nouveau bilan", "Try a built-in WOD" => "WODs intégrés",
            "No WOD yet" => "Aucun WOD",
            // pause
            "Paused" => "Pause", "Resume" => "Reprendre", "Finish" => "Terminer",
            "Discard" => "Supprimer", "End class" => "Fin du cours", "Save the score" => "Garder le score",
            "Throw away" => "Jeter", "Next part" => "Partie suivante", "Stop the plan here" => "Arrêter le plan",
            // preview
            "Go" => "Go", "Class timer" => "Chrono cours", "Battery" => "Batterie", "Stress" => "Stress",
            "Best" => "Record", "Last" => "Dernier", "more" => "de plus",
            // after the workout
            "HOW HARD WAS IT?" => "C'ÉTAIT DUR ?", "Very easy" => "Très facile", "Easy" => "Facile",
            "Moderate" => "Modéré", "Somewhat hard" => "Assez dur", "Hard" => "Dur", "Hard +" => "Dur +",
            "Very hard" => "Très dur", "Very hard +" => "Très dur +", "Near max" => "Presque max",
            "Max effort" => "Effort max", "HR recovery" => "Récup FC", "Done as" => "Fait en",
            "Load as written" => "Charge prévue", "Scaled" => "Scaled", "Lighter or modified" => "Allégé ou adapté",
            // summary
            "Save" => "Garder", "Exit" => "Quitter", "Time" => "Temps", "NEW BEST" => "RECORD !",
            "ANALYSIS" => "ANALYSE", "DETAILS" => "DÉTAILS", "Splits" => "Tours", "Load" => "Charge",
            "Mostly" => "Surtout", "Round var" => "Écart tours", "Fade" => "Baisse",
            "Work" => "Travail", "per interval" => "par intervalle", "Fitter" => "En forme",
            "vs last" => "vs dernier", "No heart rate" => "Pas de FC", "Unbroken" => "Sans pause",
            "breaks" => "pauses", "Transitions" => "Transitions", "Beats/round" => "Batt./tour",
            "Moved" => "Soulevé", "No details for this WOD" => "Pas de détails", "HR recovery in" => "Récup FC dans",
            // stats
            "This week" => "Cette semaine", "Training load" => "Charge", "Balance" => "Équilibre",
            "Strong / weak" => "Forts / faibles", "Movements" => "Mouvements", "Overall" => "Global",
            "LAST 7 DAYS" => "7 DERNIERS JOURS", "TRAINING LOAD" => "CHARGE", "WEEK PATTERN" => "PROFIL SEMAINE",
            "BALANCE, 4 WEEKS" => "ÉQUILIBRE, 4 SEM.", "STRONG / WEAK" => "FORTS / FAIBLES",
            "Pace per rep" => "Temps par rep", "Monotony" => "Monotonie", "Strain" => "Contrainte",
            "Optimal" => "Optimal", "Low: room for more" => "Faible : marge", "High: watch recovery" => "Élevée : récupère",
            "Very high: ease off" => "Très élevée : lève le pied", "Building baseline" => "Historique en cours",
            "Gym" => "Gym", "Weights" => "Haltéro", "Mono" => "Cardio", "New bests" => "Records",
            "No data yet" => "Pas encore de données", "fast" => "rapide", "slow" => "lent",
            "Workouts" => "Séances", "was" => "avant", "New report" => "Nouveau bilan",
            // coach
            "Run class plan" => "Lancer le plan", "Start" => "Départ", "Rest between parts" => "Repos entre parties",
            "Halfway alert" => "Alerte mi-temps", "1 min left alert" => "Alerte 1 min", "Big clock, no recording" => "Gros chrono, sans enregistrement",
            // sync / onboarding
            "Syncing..." => "Synchro...", "WOD updated" => "WOD à jour", "Welcome" => "Bienvenue",
            "Continue" => "Continuer", "ROUND" => "TOUR", "Rounds times" => "Temps par tour",
            "HR during the WOD" => "FC pendant le WOD", "PROGRESS" => "PROGRESSION", "Zone" => "Zone", "Phone" => "Téléphone",
            "Your WOD on the wrist: timer, reps, rounds, heart rate." => "Ton WOD au poignet : chrono, reps, tours, cardio.",
            "Garmin Connect > WODwrist > Settings > WOD text. Example: AMRAP 12; 10 burpees" => "Garmin Connect > WODwrist > Réglages > WOD text. Exemple : AMRAP 12; 10 burpees",
            "Coach page? Paste its URL in the settings, then Sync WOD. Or try a sample." => "Page du coach ? Colle son URL dans les réglages, puis Synchroniser. Ou essaie un exemple."
        } as Dictionary<String, String>;
    }
}
