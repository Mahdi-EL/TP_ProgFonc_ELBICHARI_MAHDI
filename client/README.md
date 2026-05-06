# Client

## 2.3 Robustesse OTP

**Question : Qu'apporterait la gestion du suivi de processus, 
redémarrage automatique par rapport à votre code ?**

Actuellement, la reconnexion du client est gérée manuellement 
via la fonction `connect_with_retry/5` qui retente la connexion 
de façon récursive en cas d'échec. Cette approche fonctionne 
mais reste limitée.

Si on utilisait OTP (GenServer + Supervisor) côté client :

- **Redémarrage automatique** : si le processus client plante 
  pour n'importe quelle raison (pas seulement une déconnexion 
  réseau), le Supervisor le relancerait automatiquement sans 
  intervention manuelle.

- **Gestion d'état** : l'état du client (pseudo, salon, socket) 
  serait maintenu proprement dans un GenServer plutôt que passé 
  en paramètres de fonction en fonction.

- **Let it crash** : au lieu de gérer tous les cas d'erreur 
  manuellement, on laisserait le processus planter et le 
  superviseur s'occuperait de le relancer dans un état propre.

- **Tolérance aux pannes complète** : notre code actuel ne gère 
  que la déconnexion réseau. Avec OTP, tout type de crash serait 
  géré automatiquement.