-- Создание схемы для основных таблиц
CREATE SCHEMA main AUTHORIZATION newuser;

-- Создание таблицы студентов в стандартном табличном пространстве
CREATE TABLE main.students (
    student_id SERIAL PRIMARY KEY,
    first_name VARCHAR(50),
    last_name VARCHAR(50),
    enrollment_date DATE
) TABLESPACE pg_default;

-- Создание таблицы курсов в стандартном табличном пространстве
CREATE TABLE main.courses (
    course_id SERIAL PRIMARY KEY,
    course_name VARCHAR(100),
    credits INTEGER
) TABLESPACE pg_default;

-- Создание временной таблицы для временных данных в табличном пространстве mqb89 без внешних ключей
CREATE TEMP TABLE temp_enrollments (
    temp_id SERIAL PRIMARY KEY,
    student_id INTEGER,
    course_id INTEGER,
    enrollment_date DATE
) TABLESPACE mqb89;

-- Создание временной таблицы для временных индексов в табличном пространстве utr38 без внешних ключей
CREATE TEMP TABLE temp_course_statistics (
    course_id INTEGER,
    average_grade DECIMAL(5,2)
) TABLESPACE utr38;
