# GlowRex: The Radiant Skincare Journey

## Table of content:

- [Project Overview](#project-overview)
- [Goal](#goal)
- [Data Sources](#data-sources)
- [Tools](#tools)
- [Analysis Details](#analysis-details)
- [Final Operational Metrics](#final-operational-metrics)
- [Conclusions](#conclusions)

### Project Overview

For this project, I’ll be working in Snowflake and will be analyzing data from GlowRex, a skincare company. 
The company offers a service designed to enhance users' skincare routines with expert guidance.

#### Upon registering for a GlowRex membership, individuals embark on a personalized skincare journey, which consists of the following steps:
 1. It begins with scheduling an initial video consultation with a certified dermatologist. 
 2. The consultation. It allows the dermatologist to tailor a skincare regimen to the user's unique needs and recommend specialized products.
 3. Following this personalized recommendation, users purchase the suggested products conveniently delivered quarterly for the rest of their membership period.

This structured approach ensures that users continuously receive professional dermatological advice and high-quality skincare products, creating sustained skin health improvement.

#### Top 5 Skincare Rx Products:
- AcneVanish Serum - acne_serum
- GlowBoost Moisturizer - glow_moisturizer
- ClearGlow Cleanser - clear_cleanser
- RadianceRenew Night Cream - night_cream
- SunGuard SPF Lotion - spf_lotion

### Goal:
The Company's goal is to be able to spot and fix delays in customer journey early, and to be able to find correlations of ineficciencies with decrease in revenue.
The project aims to provide a report with the turnaround time for each step in the user journey: 
1. from sign-up to first appointment, 
2. from first appointment to first order, and 
3. the total value of that first order.

### Data Sources 
The database schema is located in SQLII database, RAW_DATA schema, and includes the following tables:
- Users - Contains user signup details.
- Appointments - Holds appointment scheduling details, including the user ID, appointment status (e.g., booked, completed, canceled), and timestamps.
- rx_orders - Tracks prescription orders by the user, including the product ID

### Tools:
 - Snowflake [Click here](https://app.snowflake.com/)
 - Tableau [Click here](https://public.tableau.com/app/discover)

### Analysis Details

#### 1. Data Preparation 

I will start by preparing the data and reviewing the tables to familiarize myself with it. The next step will be performing an initial check for any data inconsistencies or missing values in the key columns used throughout the analysis. I will also check for null user_ids in the appointments table and exclude them going forward. Finally, I’ll create CTEs from our source data to make it easier to reference.

```sql
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
    )
```

#### 2. Creating a CTE for De-duplicated Appointments

I’ll write a CTE to de-duplicate appointments, including only the final status for each appointment and removing any rows with null user_id.

I’ll use a window function (ROW_NUMBER()) partitioned by user_id and appointment_date and ordered by the row created_date in descending order to get the most recent row with the latest status for each appointment. After that, I’ll filter this result to include only rows where the rank is 1, indicating the latest status and appointment status “Completed.” Then, I’ll filter it even more by selecting the first appointment from “completed” appointments for each user.

```sql
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
)
```

#### 3.  Finding the first Prescription Order after the appointment

Next, I’ll identify the first Rx order for each user; I’ll have to consider that each order might have multiple line items. Since the table has line items that duplicate order IDs, I'll use DENSE_RANK() instead of ROW_NUMBER(). This will ensure that various lines with the same OrderId will be treated equally in rank, the first invoice issued is correctly identified, and then filter it once more to keep only the first order for each user. 

```sql
first_orders AS (
    SELECT *,
    DENSE_RANK() OVER (PARTITION BY user_id
    ORDER BY transaction_date, order_number) as dr
    FROM rx_orders
    QUALIFY dr = 1
)
```

#### 4. Combining Insights into a View “first_user_journey”

The next step will be to combine tables to start shaping the view of the “first_user_journey.”

I’ll JOIN the users table with the first_completed_appt CTE I created earlier, followed by LEFT JOIN of the users, with_appts and first_orders tables. I’ll also convert created_at to a DATE format. 

```sql
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
)
```

There are multiple rows for the same user_id because users can order multiple items. Add the sum of item_amount to calculate fst_order_value per user.

```sql
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
)
```

#### 5. Calculating turnaround time

I’ll calculate the turnaround time between each step and the sign-up week to see the weekly turnaround in the next step:

1. Days between user sign-up to the first appointment.
2. Days between the first appointment and the first Rx order.

```sql
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
```

#### 6. Create a view by utilizing “CREATE VIEW”.

I’ll create a view so that the query output is saved and can be used for reporting needs.


### Final Operational Metrics

Now that the view is created, I’m going to calculate the final metric with the number of users signed up each week:

- Average time to each step.
- The percentage of users completing each step.
- Average first-order value.

```sql
final AS (
    SELECT sign_up_week,
           COUNT(user_id) AS users_sign_up,
           AVG(appt_tat) AS avg_days_to_fst_appt,
           AVG(order_tat) AS avg_days_to_fst_order,
           COUNT(appt_tat) / COUNT(*) AS pch_users_w_appt,
           COUNT (order_tat) / COUNT(*) AS pch_users_w_orders,
           AVG(fst_order_value) AS avg_fst_order_value
    FROM turnaround
    GROUP BY 1 
    ORDER BY 1
    )
```

### Conclusions

Examples of two reports are included in this project repository as CSV files as well as full SQL, I also included a link to Tableau dashboard. [Click here](https://public.tableau.com/views/GlowRexDashboard/GlowRexDashboard?:language=en-US&:sid=&:display_count=n&:origin=viz_share_link)


<img width="1514" alt="Screenshot 2024-06-29 at 12 28 23" src="https://github.com/VoronovaOlga/first-user-journey/assets/168027474/c19eea01-dd00-4b3a-9210-b159cff42367">


By looking at the turnaround time between each step week by week, we can spot delays in the new user sign-up funnel that can potentially affect the Company’s revenue. 
The chosen approach provides a broader overview of user behavior and service efficiency and helps to spot operational delays early. 


