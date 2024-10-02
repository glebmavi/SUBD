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

INSERT INTO main.students (first_name, last_name, enrollment_date)
VALUES
('Иван', 'Иванов', '2023-09-01'),
('Мария', 'Петрова', '2023-09-02'),
('Сергей', 'Сидоров', '2023-09-03'),
('Анна', 'Кузнецова', '2023-09-04'),
('Дмитрий', 'Смирнов', '2023-09-05'),
('Елена', 'Ковалёва', '2023-09-06'),
('Алексей', 'Морозов', '2023-09-07'),
('Наталья', 'Новикова', '2023-09-08'),
('Павел', 'Фёдоров', '2023-09-09'),
('Ольга', 'Лебедева', '2023-09-10');

INSERT INTO main.courses (course_name, credits)
VALUES
('Математика', 5),
('Физика', 4),
('Химия', 4),
('Информатика', 6),
('Биология', 4),
('История', 3),
('Литература', 3),
('География', 3),
('Музыка', 2),
('Изобразительное искусство', 2);

INSERT INTO temp_enrollments (student_id, course_id, enrollment_date)
VALUES
(1, 1, '2023-09-10'),
(2, 2, '2023-09-11'),
(3, 3, '2023-09-12'),
(4, 4, '2023-09-13'),
(5, 5, '2023-09-14'),
(6, 6, '2023-09-15'),
(7, 7, '2023-09-16'),
(8, 8, '2023-09-17'),
(9, 9, '2023-09-18'),
(10, 10, '2023-09-19');

INSERT INTO temp_course_statistics (course_id, average_grade)
VALUES
(1, 4.5),
(2, 4.0),
(3, 3.8),
(4, 4.7),
(5, 4.2),
(6, 3.5),
(7, 3.9),
(8, 4.1),
(9, 3.7),
(10, 3.6);

SELECT * FROM pg_catalog.pg_tables WHERE tableowner = 'newuser';

SELECT * FROM pg_tablespace;

SELECT
    spcname AS tablespace,
    relname
FROM
    pg_class
    JOIN pg_tablespace ON pg_tablespace.oid = reltablespace;

SELECT
    relname, spcname AS tablespace
FROM
    pg_class LEFT JOIN pg_tablespace ON pg_tablespace.oid = reltablespace
WHERE
    relowner = (SELECT oid FROM pg_roles WHERE rolname = 'newuser');
