
    WITH 
      
    users AS (
      SELECT *
      FROM SQLII.RAW_DATA.USERS
      ORDER BY user_id
    ),
    
    rx_orders AS (
      SELECT *
      FROM SQLII.RAW_DATA.RX_ORDERS
      ORDER BY user_id
    ),
    
    appointments AS (
      SELECT *
      FROM SQLII.RAW_DATA.APPOINTMENTS
      WHERE user_id IS NOT NULL
    ),
    
    cleaned_appts AS (
      SELECT *,
      ROW_NUMBER() OVER (PARTITION BY user_id, appointment_date
      ORDER BY created_date DESC) AS rn
      FROM appointments
    ),

    appts_status AS (
      SELECT *
      FROM cleaned_appts
      WHERE rn = 1
    ),

    completed_appts AS(
      SELECT *
      FROM appts_status
      WHERE appointment_status = 'Completed'
      ORDER BY 1,3
    ),

    first_completed_appt AS (
      SELECT *,
      ROW_NUMBER() OVER (PARTITION BY user_id
      ORDER BY appointment_date) AS first_appt
      FROM completed_appts 
      QUALIFY first_appt = 1
    ),

    first_orders AS (
      SELECT *,
      DENSE_RANK() OVER (PARTITION BY user_id
      ORDER BY transaction_date, order_number) as dr
      FROM rx_orders
      QUALIFY dr = 1
    ),

    with_appts AS(
      SELECT users.user_id,
             users.created_at,
             first_completed_appt.appointment_date AS fst_completed_appt
      FROM users
      JOIN first_completed_appt
      ON first_completed_appt.user_id = users.user_id
      ORDER BY 1,2,3
    ),

    with_orders AS(
      SELECT users.user_id,
             users.created_at::date AS sign_up,
             with_appts.fst_completed_appt,
             first_orders.order_number AS first_order_number,
             first_orders.item_amount,
             first_orders.transaction_date AS first_order_date
             FROM users
      LEFT JOIN with_appts 
          ON with_appts.user_id = users.user_id
      LEFT JOIN first_orders
          ON first_orders.user_id = with_appts.user_id
      ), 

    with_orders_agg AS (
      SELECT user_id,
             sign_up,
             fst_completed_appt,
             first_order_number,
             SUM(item_amount) AS fst_order_value,
             first_order_date
      FROM with_orders
      GROUP BY user_id,
             sign_up,
             fst_completed_appt,
             first_order_number,
             first_order_date
      ORDER BY 1
    ),

    turnaround AS(
      SELECT user_id,
             sign_up,
             DATE_TRUNC('week', sign_up)::date as sign_up_week,
             fst_completed_appt::date - sign_up::date AS appt_tat,
             fst_completed_appt,
             first_order_number,
             fst_order_value,
             first_order_date::date - fst_completed_appt AS order_tat,
             first_order_date
      FROM with_orders_agg
    )
    
    select * from turnaround;
