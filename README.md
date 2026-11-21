# Suite d'Inventaire Initial - Infrastructure Personnelle

Ce dossier regroupe les scripts d'inventaire technique initial pour **Windows** (PowerShell) et **Linux** (Bash), conçus selon une philosophie stricte de sécurité, de confidentialité et de non-ingérence.

---

## 🛡️ Principes et Garanties

1. **Lecture seule stricte** :
   - Aucune installation de paquet.
   - Aucune modification de configuration système ou réseau.
2. **Aucune élévation de privilèges** :
   - Fonctionne avec un compte standard sans privilèges élevés.
   - Aucun `RunAs`, `sudo` ou demande de mot de passe administrateur / root.
3. **Respect de la vie privée et anonymisation des identifiants matériels** :
   - **Exclus volontairement** : numéros de série (Serial Numbers), UUID matériels, adresses MAC, BSSID Wi-Fi, clés de chiffrement et mots de passe.
4. **Sécurité et atomicité du fichier de sortie** :
   - Collecte préalable en mémoire.
   - Création sécurisée avec permissions privées (`0600` sous Linux, ACL restreinte à l'utilisateur sous Windows) **avant** écriture.
   - Protection contre l'écrasement de fichier existant (`CreateNew` / `noclobber`).

---

## 📂 Contenu du dossier

| Fichier | Description |
|---|---|
| `inventaire_initial_windows_v1.2.ps1` | **Script Windows principal (v1.2)** : rapport complet, écriture mémoire atomique, ACL privée, UTF-8 sans BOM. |
| `inventaire.ps1` | Version Windows v1.1 corrigée (mode streaming direct). |
| `inventaire_initial_linux_v1.2.sh` | **Script Linux principal (v1.2)** : équivalent Bash strict, compatible Debian/Ubuntu/Fedora/Arch/Alpine. |
| `inventaire_initial_linux.sh` | Copie / alias direct du script Linux. |
| `inventaire_initial_windows_2026-11-18_23-11-57.txt` | Exemple de rapport généré sous Windows 11 avec la v1.2. |
| `inventaire_initial_2026-11-18_22-32-48.txt` | Premier rapport brut d'exécution Windows (pour historique). |

---

## 🚀 Utilisation

### Sous Windows (PowerShell 5.1 / 7+)

Ouvrez un terminal PowerShell standard (sans élévation administrateur) :

```powershell
# Génération automatique (nom horodaté dans le dossier courant)
powershell -ExecutionPolicy Bypass -File .\inventaire_initial_windows_v1.2.ps1

# Ou avec chemin personnalisé :
powershell -ExecutionPolicy Bypass -File .\inventaire_initial_windows_v1.2.ps1 -OutputPath "C:\chemin\rapport.txt"
```

### Sous Linux (Bash 4+)

Ouvrez un terminal Bash standard (en utilisateur normal, sans `sudo`) :

```bash
# Rendre le script exécutable
chmod +x ./inventaire_initial_linux_v1.2.sh

# Génération automatique (nom horodaté dans le dossier courant)
./inventaire_initial_linux_v1.2.sh

# Ou avec chemin personnalisé :
./inventaire_initial_linux_v1.2.sh /chemin/vers/mon_rapport.txt
```

---

## 📑 Structure des rapports générés (0 à 10)

1. **0 - IDENTIFICATION ET CONTEXTE** : Date, hostname, OS, Kernel / Build, Uptime, Timezone, Locale.
2. **1 - IDENTITÉ MATÉRIELLE** : Constructeur, carte-mère, BIOS, périphériques principaux (Display, Net, Storage, USB, Audio), ponts PCI (extrait filtré).
3. **2 - PROCESSEUR** : Modèle, cœurs, threads, fréquences, virtualisation, charge moyenne.
4. **3 - MÉMOIRE RAM ET SWAP** : RAM totale / libre / utilisée, swap, slots mémoire.
5. **4 - GPU ET ACCÉLÉRATEURS** : Contrôleurs graphiques, pilotes chargés, statut NVIDIA (`nvidia-smi` sans UUID).
6. **5 - STOCKAGE** : Disques physiques, partitions, volumes, occupation, statut chiffrement (BitLocker / LUKS sans clés).
7. **6 - RÉSEAU** : Interfaces (sans MAC), IP locales, routes, serveurs DNS, Wi-Fi actif (sans BSSID), sockets TCP/UDP en écoute.
8. **7 - SYSTÈME ET SERVICES** : Services en cours, conteneurs Docker/Podman actifs, virtualisation (Hyper-V, KVM, WSL).
9. **8 - OUTILS ET TECHNOLOGIES** : Détection des outils de développement et d'administration, versions clés.
10. **9 - INDICATEURS GÉNÉRAUX** : Charge globale, processeurs logiques, espace disque racine.
11. **10 - LIMITES ET INTERPRÉTATION** : Rappel des conditions de collecte et consignes de manipulation du fichier sensible.

