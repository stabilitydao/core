const { ethers, upgrades } = require('hardhat')

module.exports = async ({ getNamedAccounts, deployments, getChainId }) => {
  // type proxy address for upgrade contract
  // deployer must have upgrade access
  const upgradeProxy = null // ropsten: ''

  const { save, get } = deployments
  const { deployer } = await getNamedAccounts()
  const chainId = await getChainId()

  console.log('')

  // noinspection PointlessBooleanExpressionJS
  if (!upgradeProxy) {
    console.log(`== Gov deployment to ${hre.network.name} ==`)
    try {
      const deplpoyment = await get('Gov')
      console.log(
        `Gov already deployed to ${hre.network.name} at ${deplpoyment.address}`
      )
      return
    } catch (e) {
      // not deployed yet
    }
  } else {
    console.log(`==== Gov upgrade at ${hre.network.name} ====`)
    console.log(`Proxy address: ${upgradeProxy}`)
  }

  const token = await deployments.get('ProfitToken')
  const timelock = await deployments.get('GovTimelock')

  console.log('ChainId:', chainId)
  console.log('Deployer address:', deployer)
  console.log('ProfitToken address:', token.address)
  console.log('Timelock controller address:', timelock.address)

  // noinspection PointlessBooleanExpressionJS
  if (!upgradeProxy) {
    let votingDelay = 10
    let votingPeriod = 30
    let proposalThreshold = ethers.utils.parseEther('100') // 100.0 tokens
    if (hre.network.name == 'mainnet') {
      votingDelay = 6545 // 1 day
      votingPeriod = 3 * 6545 // 3 days
      // proposalThreshold = 100e18 // 100.0 tokens
    } else if (hre.network.name == 'ropten') {
      votingDelay = 100
      votingPeriod = 6545
      proposalThreshold = ethers.utils.parseEther('10') // 10.0 tokens
    } else if (hre.network.name == 'mumbai') {
      votingDelay = 100
      votingPeriod = 6545
      proposalThreshold = ethers.utils.parseEther('10') // 10.0 tokens
    }

    const Gov = await ethers.getContractFactory('Gov')

    const gov = await upgrades.deployProxy(
      Gov,
      [
        token.address,
        timelock.address,
        votingDelay,
        votingPeriod,
        proposalThreshold,
      ],
      {
        kind: 'uups',
      }
    )

    await gov.deployed()

    const artifact = await hre.artifacts.readArtifact('Gov')

    await save('Gov', {
      address: gov.address,
      abi: artifact.abi,
    })

    let receipt = await gov.deployTransaction.wait()
    console.log(
      `Gov proxy deployed at: ${gov.address} (block: ${
        receipt.blockNumber
      }) with ${receipt.gasUsed.toNumber()} gas`
    )

    // const TIMELOCK_ADMIN_ROLE = ethers.utils.id('TIMELOCK_ADMIN_ROLE')
    const PROPOSER_ROLE = ethers.utils.id('PROPOSER_ROLE')
    const EXECUTOR_ROLE = ethers.utils.id('EXECUTOR_ROLE')

    const timelockContract = await ethers.getContractAt(
      'GovTimelock',
      timelock.address
    )

    let tx

    tx = await timelockContract.grantRole(PROPOSER_ROLE, gov.address)
    console.log(`Grant timelock proposer role to governance (tx: ${tx.hash})`)

    tx = await timelockContract.grantRole(EXECUTOR_ROLE, gov.address)
    console.log(`Grant timelock executor role to governance (tx: ${tx.hash})`)
  } else {
    // try to upgrade
    const Gov = await ethers.getContractFactory('Gov')
    const gov = await upgrades.upgradeProxy(upgradeProxy, Gov)

    const artifact = await hre.artifacts.readArtifact('Gov')

    await save('Gov', {
      address: gov.address,
      abi: artifact.abi,
    })

    let receipt = await gov.deployTransaction.wait()
    console.log(
      `Gov upgraded through proxy: ${gov.address} (block: ${
        receipt.blockNumber
      }) with ${receipt.gasUsed.toNumber()} gas`
    )

    // hardhat verify --network r.. 0x
  }
}

module.exports.tags = ['Gov']
module.exports.dependencies = ['ProfitToken', 'GovTimelock']
