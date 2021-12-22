import styles from '../styles/EOM.module.css'
import Toolbar from '../components/toolbar.js'

export function EOM({employee}) {
    console.log(JSON.stringify(employee))
    return (
        <div className='page-container'>
            <Toolbar/>
            <div className={styles.main}>
                <h1>Employee of the Month</h1>      
                <div className={styles.employeeOfTheMonth}>
                    <h3>{employee.name}</h3>
                    <h6>{employee.position}</h6>
                    <img src={employee.image}></img>
                    <p>{employee.description}</p>   
                </div>   
            </div>
        </div>
    )

}

export const getServerSideProps = async pageContext => {
    let apiResponse
    try {apiResponse = await fetch(
        'https://my-json-server.typicode.com/portexe/next-news/employeeOfTheMonth'
    )} catch(err) {
        logger.error('Http error', err)
        return resizeBy.status(500).send()
    }
    const employee = await apiResponse.json();
    console.log("pageContext:" + pageContext.query)
    return {
        props: {
            employee: employee
        }
    }
}


export default EOM;