import Head from 'next/head'
import Image from 'next/image'
import styles from '../styles/Home.module.css'
import {Flex} from '@chakra-ui/react'
import Toolbar from '../components/toolbar.js'

export default function Home() {
  console.log("FUCK")
  return (
    <div className='page-container'>
      <Toolbar/>
      <div className={styles.main}>
        <h1>Next.js News App</h1>
        <h3>Your one stop shop for some bullshit</h3>
      </div>
    </div>
  )
}
