# Changelog

## 1.2.0

### Nouveautés
- Sexe de l'élève (ذكر / أنثى) : sélecteur à l'ajout et à la modification d'un élève, enregistré en base (migration version 3, les élèves existants sont « ذكر » par défaut). Icône ♂/♀ dans la liste des élèves.
- Félicitation arabe selon le sexe de l'élève sélectionné : `أَحْسَنْتَ` (ذكر) ou `أَحْسَنْتِ` (أنثى), avec voyelles explicites, affichée dans la bannière et lue par la voix. Sans élève sélectionné : `أَحْسَنْتَ`.

## 1.1.0

### Nouveautés
- Voix arabe : le texte lu est `أَحْسَنْتَ` (avec voyelles) et non plus « أحسنت ». La voix `ar-SA` est essayée en premier.
- Sélection manuelle d'une question : liste déroulante sur l'écran du quiz, et saut vers n'importe quelle question pendant le quiz.
- « تمرين الإحماء » devient « السؤال ».
- Élève sélectionné affiché en grand sous les boutons « تلميذ عشوائي » et « بنك الأسئلة » ; choix manuel ou tirage au sort.
- Points persistants par élève (+1 par bonne réponse, affichés dans la liste des élèves, remise à zéro possible par classe). Base de données migrée en version 2.
- Chiffres occidentaux (0-9) partout, même en arabe : dates, titre du calendrier, questions, notes, salles. Les chiffres arabes saisis au clavier sont convertis automatiquement.
- Emploi du temps : séance 9 à 17:00 et fusion automatique des séances consécutives de la même classe.
- Workflow GitHub Actions : build de l'APK et publication d'une Release à chaque push sur `main`.

### Corrections et optimisations
- La base de données ne peut plus être ouverte deux fois en parallèle au démarrage.
- La voix est arrêtée en passant à la question suivante (plus de chevauchement).
- Les puces de la note du jour regroupent les séances consécutives d'une même classe.
- Suppression ou renommage d'un élève sélectionné : la sélection est mise à jour.
- Boîtes de confirmation factorisées (`confirmDialog`).
