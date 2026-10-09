// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @dev Minimal reentrancy guard replacement for OpenZeppelin's ReentrancyGuard.
abstract contract ReentrancyGuard {
    uint256 private _status = 1;

    modifier nonReentrant() {
        require(_status == 1, "Reentrant call");
        _status = 2;
        _;
        _status = 1;
    }
}

/// @notice Tontine à bénéficiaires déterminés par l'ordre d'adhésion.
/// Chaque membre verse une garantie égale à une cotisation.
/// Un tour ne peut être clôturé que si sa cagnotte complète est financée.
contract Tontine is ReentrancyGuard {
    enum Status {
        Open,
        Active,
        Completed
    }

    struct Circle {
        address creator;
        uint256 contribution;
        uint256 maxMembers;
        uint256 roundDuration;
        uint256 currentRound;
        uint256 roundDeadline;
        Status status;
    }

    Circle[] public circles;

    mapping(uint256 => address[]) public members;
    mapping(uint256 => mapping(address => bool)) public isMember;
    mapping(uint256 => mapping(address => uint256)) public guarantee;
    mapping(uint256 => mapping(uint256 => mapping(address => bool))) public paid;
    mapping(uint256 => mapping(uint256 => uint256)) public paidCount;
    mapping(address => uint256) public pending;

    event CircleCreated(
        uint256 indexed id,
        address indexed creator,
        uint256 contribution,
        uint256 maxMembers,
        uint256 roundDuration
    );
    event Joined(uint256 indexed id, address indexed member);
    event Left(uint256 indexed id, address indexed member);
    event CircleStarted(uint256 indexed id);
    event Contributed(
        uint256 indexed id,
        uint256 indexed round,
        address indexed member
    );
    event Defaulted(
        uint256 indexed id,
        uint256 indexed round,
        address indexed member
    );
    event RoundClosed(
        uint256 indexed id,
        uint256 indexed round,
        address indexed beneficiary,
        uint256 pot
    );
    event CircleCompleted(uint256 indexed id);
    event GuaranteeClaimed(
        uint256 indexed id,
        address indexed member,
        uint256 amount
    );
    event Withdrawn(address indexed who, uint256 amount);

    // ---------- Création / adhésion ----------

    function createCircle(
        uint256 contribution,
        uint256 maxMembers,
        uint256 roundDuration
    ) external returns (uint256 id) {
        require(contribution > 0, "Cotisation nulle");
        require(maxMembers >= 2 && maxMembers <= 20, "2 a 20 membres");
        require(roundDuration >= 1 minutes, "Duree trop courte");

        circles.push(
            Circle({
                creator: msg.sender,
                contribution: contribution,
                maxMembers: maxMembers,
                roundDuration: roundDuration,
                currentRound: 0,
                roundDeadline: 0,
                status: Status.Open
            })
        );

        id = circles.length - 1;
        emit CircleCreated(
            id,
            msg.sender,
            contribution,
            maxMembers,
            roundDuration
        );
    }

    /// @notice Rejoint un cercle en déposant une garantie égale à une cotisation.
    function join(uint256 id) external payable {
        require(id < circles.length, "Cercle inexistant");

        Circle storage c = circles[id];
        require(c.status == Status.Open, "Cercle ferme");
        require(!isMember[id][msg.sender], "Deja membre");
        require(msg.value == c.contribution, "Montant incorrect");

        isMember[id][msg.sender] = true;
        guarantee[id][msg.sender] = msg.value;
        members[id].push(msg.sender);

        emit Joined(id, msg.sender);

        if (members[id].length == c.maxMembers) {
            c.status = Status.Active;
            c.roundDeadline = block.timestamp + c.roundDuration;
            emit CircleStarted(id);
        }
    }

    /// @notice Quitte un cercle encore ouvert et récupère sa garantie via pending.
    function leaveCircle(uint256 id) external {
        require(id < circles.length, "Cercle inexistant");

        Circle storage c = circles[id];
        require(c.status == Status.Open, "Cercle demarre");
        require(isMember[id][msg.sender], "Pas membre");

        address[] storage list = members[id];

        for (uint256 i = 0; i < list.length; i++) {
            if (list[i] == msg.sender) {
                // L'ordre final sera celui des membres présents au démarrage.
                list[i] = list[list.length - 1];
                list.pop();
                break;
            }
        }

        isMember[id][msg.sender] = false;

        uint256 amount = guarantee[id][msg.sender];
        guarantee[id][msg.sender] = 0;
        pending[msg.sender] += amount;

        emit Left(id, msg.sender);
    }

    // ---------- Tours ----------

    /// @notice Verse la cotisation du tour en cours.
    /// Après l'échéance, les membres peuvent encore payer si le tour n'a pas été clôturé.
    function contribute(uint256 id) external payable {
        require(id < circles.length, "Cercle inexistant");

        Circle storage c = circles[id];
        require(c.status == Status.Active, "Cercle inactif");
        require(isMember[id][msg.sender], "Pas membre");
        require(!paid[id][c.currentRound][msg.sender], "Deja cotise");
        require(msg.value == c.contribution, "Montant incorrect");

        paid[id][c.currentRound][msg.sender] = true;
        paidCount[id][c.currentRound] += 1;

        emit Contributed(id, c.currentRound, msg.sender);
    }

    /// @notice Clôture un tour si tout le monde a payé, ou si le délai est dépassé
    /// et les garanties disponibles suffisent à compléter la cagnotte.
    function closeRound(uint256 id) external {
        require(id < circles.length, "Cercle inexistant");

        Circle storage c = circles[id];
        require(c.status == Status.Active, "Cercle inactif");

        uint256 round = c.currentRound;
        bool everyonePaid = paidCount[id][round] == c.maxMembers;

        require(
            everyonePaid || block.timestamp > c.roundDeadline,
            "Tour en cours"
        );

        uint256 pot = paidCount[id][round] * c.contribution;
        address[] storage list = members[id];

        // Vérifie d'abord que les garanties couvrent tous les impayés.
        for (uint256 i = 0; i < list.length; i++) {
            address member = list[i];

            if (!paid[id][round][member]) {
                require(
                    guarantee[id][member] >= c.contribution,
                    "Garantie insuffisante : tour bloque"
                );
                pot += c.contribution;
            }
        }

        require(
            pot == c.contribution * c.maxMembers,
            "Cagnotte incomplete"
        );

        // Déduit les garanties après validation complète.
        for (uint256 i = 0; i < list.length; i++) {
            address member = list[i];

            if (!paid[id][round][member]) {
                guarantee[id][member] -= c.contribution;
                emit Defaulted(id, round, member);
            }
        }

        address beneficiary = list[round];
        pending[beneficiary] += pot;

        emit RoundClosed(id, round, beneficiary, pot);

        c.currentRound = round + 1;

        if (c.currentRound == c.maxMembers) {
            c.status = Status.Completed;
            emit CircleCompleted(id);
        } else {
            c.roundDeadline = block.timestamp + c.roundDuration;
        }
    }

    /// @notice Récupère la garantie restante après la fin du cycle.
    function claimGuarantee(uint256 id) external {
        require(id < circles.length, "Cercle inexistant");
        require(circles[id].status == Status.Completed, "Cycle non termine");
        require(isMember[id][msg.sender], "Pas membre");

        uint256 amount = guarantee[id][msg.sender];
        require(amount > 0, "Rien a recuperer");

        guarantee[id][msg.sender] = 0;
        pending[msg.sender] += amount;

        emit GuaranteeClaimed(id, msg.sender, amount);
    }

    /// @notice Retire les fonds crédités dans pending.
    function withdraw() external nonReentrant {
        uint256 amount = pending[msg.sender];
        require(amount > 0, "Rien a retirer");

        pending[msg.sender] = 0;

        (bool success, ) = payable(msg.sender).call{value: amount}("");
        require(success, "Transfert echoue");

        emit Withdrawn(msg.sender, amount);
    }

    // ---------- Lecture ----------

    function circlesCount() external view returns (uint256) {
        return circles.length;
    }

    function membersCount(uint256 id) external view returns (uint256) {
        require(id < circles.length, "Cercle inexistant");
        return members[id].length;
    }
}