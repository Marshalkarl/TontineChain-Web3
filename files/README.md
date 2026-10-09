# Tontine

Application décentralisée de tontine basée sur un contrat intelligent Ethereum. Les membres rejoignent un cercle en déposant une garantie, cotisent à chaque tour et reçoivent la cagnotte chacun leur tour. Le contrat gère les retards de paiement, les garanties et les retraits.

## Fonctionnement

1. Un utilisateur crée un cercle en choisissant le montant de cotisation, le nombre de membres et la durée des tours.
2. Les membres rejoignent le cercle en déposant une garantie égale à une cotisation.
3. Quand le cercle est complet, le cycle démarre. L’ordre des membres détermine le bénéficiaire de chaque tour.
4. Les membres cotisent pendant le tour. Une fois que tout le monde a payé, ou que le délai est dépassé, n’importe qui peut clôturer le tour.
5. En cas d’impayé, la garantie du membre concerné peut compléter la cagnotte.
6. À la fin du cycle, les membres peuvent réclamer leur garantie restante et retirer leurs fonds.

Les fonds dus sont crédités dans `pending`. Chaque membre doit appeler `withdraw()` pour les récupérer.

## Contrat intelligent

Le contrat `Tontine` est écrit en Solidity `^0.8.20` et utilise `ReentrancyGuard` d’OpenZeppelin pour protéger la fonction de retrait.

### Règles principales

- Un cercle accepte entre **2 et 20 membres**.
- La cotisation doit être supérieure à zéro.
- La durée d’un tour doit être d’au moins **1 minute**.
- La garantie versée lors de l’adhésion est égale à une cotisation.
- Un membre peut quitter un cercle tant qu’il est ouvert ; sa garantie est alors créditée dans son solde retirable.
- Les membres cotisent une fois par tour.
- Un tour peut être clôturé lorsque tous les membres ont payé ou après l’expiration du délai.
- Le bénéficiaire est choisi selon l’ordre des membres dans le tableau du cercle.
- Une fois le cycle terminé, chaque membre peut réclamer sa garantie restante.

## Fonctions du contrat

| Fonction | Description |
|---|---|
| `createCircle(contribution, maxMembers, roundDuration)` | Crée un cercle et renvoie son identifiant. |
| `join(id)` | Rejoint un cercle en déposant la garantie requise. |
| `leave(id)` | Quitte un cercle encore ouvert et crédite la garantie dans `pending`. |
| `contribute(id)` | Verse la cotisation du tour en cours. |
| `closeRound(id)` | Clôture le tour et crédite la cagnotte au bénéficiaire. |
| `claimGuarantee(id)` | Réclame la garantie restante après la fin du cycle. |
| `withdraw()` | Retire les fonds disponibles dans `pending`. |
| `circlesCount()` | Renvoie le nombre de cercles créés. |
| `membersCount(id)` | Renvoie le nombre de membres d’un cercle. |

## Tests

Les tests fournis utilisent **Hardhat**, **Chai** et `@nomicfoundation/hardhat-network-helpers`. Ils couvrent notamment :

- le démarrage d’un cercle complet ;
- le refus d’un montant incorrect ;
- le départ d’un membre avant le démarrage ;
- le paiement et la clôture d’un tour ;
- le refus de clôturer un tour avant qu’il soit terminé ;
- l’utilisation de la garantie en cas d’impayé ;
- la fin d’un cycle et la récupération de la garantie.

Pour lancer les tests dans un projet Hardhat configuré :

```bash
npx hardhat test
```

## Installation et déploiement

Ce dépôt contient le contrat et ses tests. Pour l’utiliser, placez le contrat dans un projet Hardhat configuré avec Solidity `0.8.20` et OpenZeppelin Contracts, puis installez les dépendances du projet.

Exemple de dépendances :

```bash
npm install --save-dev hardhat
npm install @openzeppelin/contracts
npm install --save-dev chai @nomicfoundation/hardhat-network-helpers
```

Compilez le contrat et lancez les tests :

```bash
npx hardhat compile
npx hardhat test
```

Le déploiement nécessite un script et une configuration réseau adaptés. Après le déploiement, l’application front-end doit utiliser l’adresse du contrat déployé et son ABI.

## Technologies

- Solidity `^0.8.20`
- OpenZeppelin `ReentrancyGuard`
- Hardhat
- Ethers.js
- Chai

## Avertissement

Ce projet ne garantit pas qu’un bénéficiaire recevra des fonds si les cotisations et les garanties disponibles ne suffisent pas. Testez soigneusement le contrat et faites-le auditer avant toute utilisation avec des fonds réels.