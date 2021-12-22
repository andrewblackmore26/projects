import {data} from '../data/data.ts'
import styles from '../styles/Card.module.css'

function Card(props) {
    let str = JSON.stringify(data);
    console.log(props)
    console.log(str)
    return(
        <div classname={styles.container}>            
            <a href="https://nextjs.org/docs" className={styles.card}>
                <img classname={styles.img} src="clean_mwangBlack.png"/>
                <h2>Documentation &rarr;</h2>
                <p>Find in-depth information about Next.js features and API.</p>
            </a>
        </div>
    )
}


export default Card;