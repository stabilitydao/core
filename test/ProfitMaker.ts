import { expect } from 'chai'
import { ethers, upgrades } from 'hardhat'
const { time } = require('@openzeppelin/test-helpers')
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers'
import {
  ProfitMaker,
  ProfitMaker__factory,
  ProfitToken,
  ProfitToken__factory,
} from '../typechain-types'

describe('ProfitMaker NFT', function () {
  let profitToken: ProfitToken
  let profitMaker: ProfitMaker
  let _deployer: SignerWithAddress
  let _devFund: SignerWithAddress
  let _tester: SignerWithAddress

  beforeEach(async function () {
    const [deployer, tester, devFund] = await ethers.getSigners()

    _deployer = deployer
    _tester = tester
    _devFund = devFund

    const profitTokenFactory = (await ethers.getContractFactory(
      'ProfitToken'
    )) as ProfitToken__factory
    profitToken = await profitTokenFactory.deploy(_devFund.address)
    await profitToken.deployed()

    profitMaker = <ProfitMaker>(
      await upgrades.deployProxy(
        <ProfitMaker__factory>await ethers.getContractFactory('ProfitMaker'),
        [profitToken.address],
        { kind: 'uups' }
      )
    )
  })

  it('Deployed', async function () {
    expect(await profitMaker.name()).to.be.equal('Profit Maker')
    expect(await profitMaker.symbol()).to.be.equal('PM')
    expect(await profitMaker.totalSupply()).to.be.equal(0)
    expect(
      await profitMaker.supportsInterface(ethers.utils.hexlify([1, 3, 4, 5]))
    ).to.eq(false)
  })

  it('Upgrades', async function () {
    const factory = (await ethers.getContractFactory(
      'ProfitMaker'
    )) as ProfitMaker__factory

    profitMaker = (await upgrades.upgradeProxy(
      profitMaker.address,
      factory
    )) as ProfitMaker

    await profitMaker.deployed()
  })

  it('Mint', async function () {
    const color = 10,
      color2 = 20
    await expect(
      profitMaker.safeMint(_tester.address, color)
    ).to.be.revertedWith('Not enough PROFIT tokens')
    await profitToken
      .connect(_devFund)
      .transfer(_tester.address, ethers.utils.parseEther('10000'))
    expect(await profitToken.balanceOf(_tester.address)).to.equal(
      ethers.utils.parseEther('10000')
    )
    await expect(
      profitMaker.connect(_tester).safeMint(_tester.address, color)
    ).to.be.revertedWith('Mint is not available right now')
    const now = (
      await ethers.provider.getBlock(await ethers.provider.getBlockNumber())
    ).timestamp
    await profitMaker.setMintState(now, now + 86400, 3)
    await ethers.provider.send('evm_mine', [])
    await expect(
      profitMaker.connect(_tester).safeMint(_tester.address, color)
    ).to.be.revertedWith('ERC20: insufficient allowance')
    await profitToken
      .connect(_tester)
      .approve(profitMaker.address, ethers.utils.parseEther('10000'))
    await profitMaker.connect(_tester).safeMint(_tester.address, color)
    expect(await profitMaker.balanceOf(_tester.address)).to.equal(1)
    expect(await profitToken.balanceOf(_tester.address)).to.equal(0)
    expect(await profitToken.balanceOf(profitMaker.address)).to.equal(
      ethers.utils.parseEther('10000')
    )
    await expect(
      profitMaker.safeMint(_tester.address, color)
    ).to.be.revertedWith('Not enough PROFIT tokens')
    expect(await profitMaker.ownerOf(0)).to.equal(_tester.address)
    expect(await profitMaker.tokenURI(0)).to.be.equal(
      'https://stabilitydao.org/api/maker/0'
    )

    expect(await profitMaker.props(0)).to.eql([color, 1])

    await profitToken
      .connect(_devFund)
      .transfer(_tester.address, ethers.utils.parseEther('30000'))
    await profitToken
      .connect(_tester)
      .approve(profitMaker.address, ethers.utils.parseEther('30000'))
    await expect(
      profitMaker.connect(_tester).safeMint(_tester.address, color)
    ).to.be.revertedWith('This color already used')
    await profitMaker.connect(_tester).safeMint(_tester.address, color2)
    await profitMaker.connect(_tester).safeMint(_tester.address, 60)
    expect(await profitMaker.ownerOf(1)).to.equal(_tester.address)
    expect((await profitMaker.ownerTokenIds(_tester.address))[0]).to.eq('0')
    expect((await profitMaker.ownerTokenIds(_tester.address))[1]).to.eq('1')
    await expect(
      profitMaker.ownerTokenIds(_devFund.address)
    ).to.be.revertedWith('Owner dont have tokens')
    expect(await profitMaker.props(0)).to.eql([color, 1])
    expect(await profitMaker.props(1)).to.eql([color2, 1])
    expect(await profitMaker.epoch()).to.eq(1)
    await expect(
      profitMaker.connect(_tester).safeMint(_tester.address, 5)
    ).to.be.revertedWith('This epoch tokens have already been minted')
  })

  it('Vesting', async function () {
    await profitToken
      .connect(_devFund)
      .transfer(_tester.address, ethers.utils.parseEther('10000'))
    await profitToken
      .connect(_devFund)
      .transfer(_deployer.address, ethers.utils.parseEther('10000'))
    let now = (
      await ethers.provider.getBlock(await ethers.provider.getBlockNumber())
    ).timestamp
    await profitMaker.setMintState(now, now + 86400, 10)
    await profitToken
      .connect(_tester)
      .approve(profitMaker.address, ethers.utils.parseEther('10000'))
    await profitToken
      .connect(_deployer)
      .approve(profitMaker.address, ethers.utils.parseEther('10000'))
    await profitMaker.connect(_tester).safeMint(_tester.address, 2)
    await profitMaker.connect(_deployer).safeMint(_deployer.address, 3)

    await expect(
      profitMaker.releaseToBalance(profitToken.address)
    ).to.be.revertedWith('Zero to release')
    await profitMaker.setUnlock(profitToken.address, now + 1000, 1000)

    await time.increase(time.duration.seconds(994))

    now = (
      await ethers.provider.getBlock(await ethers.provider.getBlockNumber())
    ).timestamp

    // 20 000 / 1000
    expect(await profitMaker.vestedAmount(profitToken.address, now)).to.eq(
      ethers.utils.parseEther('20')
    )

    await time.increase(1)

    now = (
      await ethers.provider.getBlock(await ethers.provider.getBlockNumber())
    ).timestamp
    expect(await profitMaker.vestedAmount(profitToken.address, now)).to.equal(
      ethers.utils.parseEther('40')
    )

    await expect(profitMaker.releaseToBalance(profitToken.address)).to.be.not
      .reverted

    expect((await profitMaker.unlocks(profitToken.address))[2]).to.equal(
      ethers.utils.parseEther('60')
    )

    // unlock released / 2
    expect(await profitMaker.balanceToHarvest(profitToken.address, 1)).to.equal(
      ethers.utils.parseEther('30')
    )

    await profitMaker.harvest(profitToken.address, 1)
    await profitMaker.connect(_tester).harvest(profitToken.address, 0)

    expect(await profitToken.balanceOf(_deployer.address)).to.eq(
      ethers.utils.parseEther('30')
    )
    expect(await profitToken.balanceOf(_tester.address)).to.eq(
      ethers.utils.parseEther('30')
    )

    expect(await profitMaker.balanceToHarvest(profitToken.address, 1)).to.equal(
      ethers.utils.parseEther('0')
    )

    await time.increase(time.duration.second)
    await expect(profitMaker.releaseToBalance(profitToken.address)).to.be.not
      .reverted

    await profitMaker.harvest(profitToken.address, 1)
    await profitMaker.connect(_tester).harvest(profitToken.address, 0)

    expect(await profitToken.balanceOf(_deployer.address)).to.eq(
      ethers.utils.parseEther('70')
    )
    expect(await profitToken.balanceOf(_tester.address)).to.eq(
      ethers.utils.parseEther('70')
    )

    await time.increase(time.duration.seconds(1000))

    await expect(profitMaker.releaseToBalance(profitToken.address)).to.be.not
      .reverted

    // unlock released / 2
    expect(await profitMaker.balanceToHarvest(profitToken.address, 1)).to.equal(
      ethers.utils.parseEther('9930')
    )
    expect(
      await profitMaker
        .connect(_tester)
        .balanceToHarvest(profitToken.address, 0)
    ).to.equal(ethers.utils.parseEther('9930'))
  })
})
