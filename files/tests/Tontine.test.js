const { expect } = require("chai");
const { ethers } = require("hardhat");
const { time } = require("@nomicfoundation/hardhat-network-helpers");

describe("Tontine", () => {
  let t, alice, bob, carol;
  const c = ethers.parseEther("0.1");
  const DAY = 24 * 3600;

  async function fillCircle() {
    await t.connect(alice).join(0, { value: c });
    await t.connect(bob).join(0, { value: c });
    await t.connect(carol).join(0, { value: c });
  }

  beforeEach(async () => {
    [, alice, bob, carol] = await ethers.getSigners();
    t = await (await ethers.getContractFactory("Tontine")).deploy();
    await t.connect(alice).createCircle(c, 3, 7 * DAY);
  });

  it("démarre quand le cercle est complet", async () => {
    await t.connect(alice).join(0, { value: c });
    expect((await t.circles(0)).status).to.equal(0n); // Open
    await t.connect(bob).join(0, { value: c });
    await t.connect(carol).join(0, { value: c });
    expect((await t.circles(0)).status).to.equal(1n); // Active
  });

  it("refuse un montant incorrect", async () => {
    await expect(t.connect(alice).join(0, { value: c - 1n })).to.be.revertedWith("Montant incorrect");
  });

  it("permet de quitter avant le démarrage", async () => {
    await t.connect(alice).join(0, { value: c });
    await t.connect(alice).leave(0);
    expect(await t.pending(alice.address)).to.equal(c);
  });

  it("tour complet : le premier membre reçoit la cagnotte", async () => {
    await fillCircle();
    for (const s of [alice, bob, carol]) await t.connect(s).contribute(0, { value: c });
    await t.closeRound(0);
    expect(await t.pending(alice.address)).to.equal(c * 3n);
    await expect(t.connect(alice).withdraw()).to.changeEtherBalance(alice, c * 3n);
  });

  it("refuse de clôturer un tour en cours", async () => {
    await fillCircle();
    await t.connect(alice).contribute(0, { value: c });
    await expect(t.closeRound(0)).to.be.revertedWith("Tour en cours");
  });

  it("impayé : la garantie du défaillant complète la cagnotte", async () => {
    await fillCircle();
    await t.connect(alice).contribute(0, { value: c });
    await t.connect(bob).contribute(0, { value: c });
    await time.increase(7 * DAY + 1);
    await t.closeRound(0);
    expect(await t.pending(alice.address)).to.equal(c * 3n);
    expect(await t.guarantee(0, carol.address)).to.equal(0n);
  });

  it("cycle complet : chacun reçoit une fois et récupère sa garantie", async () => {
    await fillCircle();
    for (let round = 0; round < 3; round++) {
      for (const s of [alice, bob, carol]) await t.connect(s).contribute(0, { value: c });
      await t.closeRound(0);
    }
    expect((await t.circles(0)).status).to.equal(2n); // Completed
    await t.connect(bob).claimGuarantee(0);
    expect(await t.pending(bob.address)).to.equal(c * 3n + c); // sa cagnotte + sa garantie
  });
});
