# 00 - Accesos y cuentas SAP requeridas

> **Pregunta que responde este documento:** ¿basta con una suscripcion a SAP BTP
> para desarrollar todo GeoRisk? **No.** Se requieren 3 origenes de acceso distintos.

---

## 1. Resumen ejecutivo

| Servicio del reto | ¿Esta en SAP BTP Trial? | Como se obtiene |
|---|---|---|
| SAP HANA Cloud | ✅ Si | Instancia desde el cockpit de BTP Trial |
| SAP Build Process Automation | ✅ Si | Suscripcion desde el cockpit de BTP Trial |
| SAP Build Work Zone, standard edition | ✅ Si | Suscripcion desde el cockpit de BTP Trial |
| **SAP Analytics Cloud** | ❌ **No** | **Trial propio e independiente** (registro aparte) |
| **SAP Joule + Joule Studio** | ❌ **No** | **Solo via subcuenta de NTT DATA** (no hay trial publico) |

**Conclusion:** SAP BTP es la plataforma paraguas y cubre 3 de los 5 servicios.
SAP Analytics Cloud se registra por separado y SAP Joule depende enteramente
de que NTT DATA lo habilite.

---

## 2. Que debe entregar la organizacion del hackaton

El enunciado del reto (HKT-2026-T2) indica:

> *"Servicios SAP base: Servicios habilitados en modalidad Trial para el evento."*
> *"Extension opcional: SAP Joule + Joule Studio desde la subcuenta de NTT DATA."*

Es decir: **el equipo no debe contratar ni pagar nada.** La organizacion entrega
los accesos. Lo que si debe hacer el equipo es **confirmar por escrito y con
anticipacion** que recibira:

- [ ] Usuario y subcuenta BTP (con rol para crear instancias) o instancias ya creadas
- [ ] Instancia de SAP HANA Cloud **con el dataset comun ya cargado** + credenciales
- [ ] Tenant de SAP Analytics Cloud + usuario con rol de modelador (no solo viewer)
- [ ] Suscripcion activa a SAP Build Process Automation
- [ ] Suscripcion activa a SAP Build Work Zone, standard edition
- [ ] (Opcional) Acceso a la subcuenta NTT DATA con Joule + Joule Studio

> ⚠️ **Pedir esto por escrito minimo 48 h antes del evento.** El acceso tardio es
> el riesgo numero 1 del proyecto (ver `docs/07-supuestos-limitaciones.md`).

---

## 3. Cuenta propia de practica (recomendado antes del evento)

Independientemente de lo que entregue la organizacion, conviene levantar un
ambiente propio para practicar. La curva de aprendizaje de HANA Cloud + SAC no
se absorbe el mismo dia del hackaton.

### 3.1 SAP BTP Trial

- Registro: portal de SAP BTP, opcion *Trial account*.
- Duracion: 90 dias, renovable.
- Cubre: HANA Cloud, Build Process Automation, Build Work Zone standard edition.

**Region:** elegir una region donde los tres servicios esten disponibles
(tipicamente `US East (VA)` o `Europe (Frankfurt)`). Si se elige mal, algunos
servicios simplemente **no aparecen en el catalogo** y la subcuenta trial no se
puede mover de region: habria que rehacerla.

**Trampa critica — la instancia de HANA Cloud se detiene sola:**
en trial, HANA Cloud se apaga automaticamente cada dia para ahorrar recursos.
Hay que **reiniciarla manualmente** desde el cockpit y tarda varios minutos en
volver a estar disponible. Si el dia de la demo nadie la arranco, no hay datos.

> ✅ **Accion para el dia del evento:** designar a una persona responsable de
> arrancar HANA Cloud a primera hora y verificarlo otra vez antes de la demo.

**Trial vs Free Tier:** existe tambien el modelo *Free Tier* dentro de una cuenta
Pay-As-You-Go. No caduca a los 90 dias y permite escalar a produccion, pero
requiere registrar una tarjeta. Para un hackaton, **Trial es suficiente**.

### 3.2 SAP Analytics Cloud

- Registro **independiente** desde la pagina de producto de SAP Analytics Cloud,
  opcion de prueba gratuita.
- Duracion tipica: ~30 dias (mas corta que BTP Trial).
- **Registrarlo cerca de la fecha del evento** para que no caduque antes.

**Requisito clave:** el usuario debe tener rol de **modelador / creador de
historias**, no solo de visualizacion. Con un rol de viewer no se pueden crear
los modelos ni el scoring.

**Conexion a HANA Cloud:** SAC se conecta a HANA Cloud mediante una conexion
remota. Es el punto de integracion mas fragil del proyecto: requiere que la
instancia de HANA acepte conexiones externas (lista de IPs permitidas) y
credenciales validas. **Probar esta conexion en la Fase 0**, no el ultimo dia.

### 3.3 SAP Joule + Joule Studio

- **No hay trial publico.** Requiere licencia comercial.
- Unica via para el hackaton: la subcuenta que habilite NTT DATA.
- Si NTT DATA no lo habilita, **Joule queda fuera de alcance** y no debe
  bloquear el resto del proyecto (es un bonus explicito en el enunciado).

> 📌 **Decision de arquitectura:** el proyecto se construye de forma que Joule sea
> una capa aditiva. Si no hay acceso, los 8 entregables obligatorios se cumplen
> igual. Ver `docs/06-joule-skills.md` para el plan de contingencia.

---

## 4. Orden de activacion recomendado

```
1. Cuenta BTP Trial ......................... (hacer ya, para practicar)
   └─ region correcta
   └─ instancia HANA Cloud
   └─ suscripcion Build Process Automation
   └─ suscripcion Build Work Zone standard

2. Trial de SAP Analytics Cloud ............. (cerca del evento, caduca antes)
   └─ verificar rol de modelador
   └─ probar conexion a HANA Cloud  <-- punto critico

3. Confirmar con NTT DATA ................... (48 h antes, por escrito)
   └─ accesos oficiales del evento
   └─ dataset comun precargado
   └─ disponibilidad de Joule (si/no)
```

---

## 5. Checklist de verificacion (dia del evento, primeras 2 horas)

- [ ] Puedo entrar al cockpit de BTP y veo la subcuenta del evento
- [ ] La instancia de HANA Cloud esta **arrancada** (no solo creada)
- [ ] Puedo ejecutar `SELECT * FROM <tabla> LIMIT 10` sobre el dataset comun
- [ ] Conozco el **nombre real del esquema y de la tabla** del dataset comun
- [ ] Puedo entrar a SAC con rol de modelador
- [ ] La conexion SAC → HANA Cloud devuelve datos
- [ ] Build Process Automation abre el Lobby y permite crear un proyecto
- [ ] Work Zone permite crear un site
- [ ] (Opcional) Joule Studio accesible

> Si el punto 4 falla (no se conoce el esquema/tabla real), usar el dataset
> propio generado con `data/generar_dataset.py` y adaptar los nombres en
> `sql/01_ddl_tablas.sql`. El modelo de scoring no cambia.
