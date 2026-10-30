# Criterios de calidad de la UI

El usuario tiene que conseguir lo que vino a hacer con el menor esfuerzo posible, en cualquier pantalla y en su idioma, leerlo sin esfuerzo y ver una interfaz coherente, sencilla y agradable de una pantalla a otra. Estas reglas son el listón: se miden, no se opinan. Un incumplimiento es un hallazgo con su medida; no hace falta justificarlo con nada más, y **bloquea el cierre del encargo** hasta que lo revalides corregido.

Bloques: responsive, desplazamientos y clics (R1-R5, R9), foco y teclado (R6, R16), color y contraste (R7, R15), avisos y errores (R8, R11, R18), coherencia (R10), reglas del proyecto (R12), idioma (R13), legibilidad (R14), formularios (R17) y una interfaz sencilla y bonita (R19).

## Índice
1. Reglas
2. Anchuras de prueba
3. Cómo medir (fragmentos para el navegador)
4. Contar clics y desplazamientos de un flujo
5. Formato de las propuestas

## 1. Reglas

**R1. Sin desplazamiento horizontal.** A 320 px y a 375 px de ancho, la página no desplaza en horizontal (`scrollWidth` ≤ ancho de la ventana). Única excepción: una tabla de datos, un mapa o un diagrama que necesitan las dos dimensiones, y solo dentro de su propio contenedor desplazable, nunca la página entera. Aun así, en móvil se propone otra presentación (tarjetas, columnas plegables). Segunda excepción: una barra de pestañas o de filtros que se desplaza dentro de su propio contenedor, siempre que se lleve sola a la vista el elemento activo y siempre asome el anterior y el siguiente. Además, un fundido o un indicador tiene que señalar el lado por el que hay más. Si falta cualquiera de las tres cosas, es FALLO. Cualquier otro desplazamiento horizontal es FALLO. Si el peer doc la declara en `{{ui_decisions}}`, es una decisión ya tomada y no un fallo; si dudas, pregúntaselo a Code. *Porqué: en móvil obliga a moverse en dos ejes para leer una sola cosa; una barra que recentra sola y anuncia que hay más no obliga a buscar.*

Compruébalo como lo haría una persona: con capturas y ampliaciones de la zona, y pulsando con clics reales el elemento cortado del borde. Las medidas por script sirven de apoyo, pero no sustituyen a lo que se ve. Si la ventana del navegador es más estrecha que el ancho que quieres emular, la captura sale reducida: pide que abran la ventana entera antes de juzgar a ese tamaño.

**R2. Desplazamiento vertical mínimo.** Compacta: quita márgenes y rellenos que no separan nada, títulos con aire de sobra, bloques apilados que caben en una fila y avisos repetidos. En móvil (375×812), lo que va encima del contenido principal de la página (avisos, cabecera, título, filtros) no pasa de 200 px. La paginación va debajo de la lista, no encima. Los filtros y el buscador van en una fila. Una lista en móvil no ocupa una pantalla por elemento si el contenido cabe en dos columnas compactas. *Porqué: cada pantalla de más es un gesto más en cada visita.*

**R3. La acción principal se ve sin desplazarse.** En cada pantalla de un flujo, la acción principal (añadir, continuar, pagar, guardar) está dentro de la primera pantalla al cargar o fija en la parte inferior en móvil. *Porqué: si el usuario tiene que buscarla, el flujo se corta ahí.*

**R4. Objetivos táctiles.**
- Todo elemento pulsable mide al menos 44×44 px en móvil; la acción principal, 48 px de alto.
- Entre dos objetivos contiguos hay al menos 8 px.
- Por debajo de 24×24 px es FALLO grave (es el mínimo de accesibilidad: un objetivo menor solo vale si un círculo de 24 px centrado en él no toca a otro objetivo). Entre 24 y 44 px en móvil, FALLO de usabilidad.
- Única excepción: un enlace dentro de una frase de texto.
- *Porqué: un dedo no es un puntero; los objetivos pequeños o pegados provocan toques equivocados.*

**R5. Ningún elemento interactivo dentro de otro.** Nada de `<button>` dentro de `<a>`, ni enlace dentro de enlace. *Porqué: el lector de pantalla y el teclado no saben cuál de los dos es la acción.*

**R6. Foco visible y no tapado.** Al recorrer con el tabulador, el elemento con foco se ve siempre: el indicador contrasta al menos 3:1 con lo que lo rodea, y ninguna barra fija, banner de cookies ni aviso lo cubre.

**R7. Contraste.**
- Texto normal: al menos 4,5:1 con su fondo. Texto grande (24 px, o 18,7 px en negrita, en adelante): al menos 3:1.
- Bordes de campos, iconos con significado, estados de los controles (marcado, activo) y partes de un gráfico: al menos 3:1 con lo que tienen al lado.
- Se mide sobre el fondo real: un texto encima de una imagen o de un degradado se mide en su punto más desfavorable.
- El estado nunca se indica solo con color: lleva texto, icono o forma.

**R8. Cada acción responde y propone el paso siguiente.** Tras una acción, el aviso dice qué ha pasado y, si hay un siguiente paso natural, lo ofrece con un botón (por ejemplo, «Añadido al carrito · Ver carrito»). Un aviso sin salida obliga a buscar el camino.

**R9. Mínimo de clics.**
- Un dato que el sistema ya conoce no se vuelve a pedir: se muestra resumido con «Cambiar».
- Un aviso que se acepta una vez no se repite dentro de la misma sesión.
- Una confirmación solo existe antes de algo irreversible o con dinero, y entonces se mantiene: se acorta, no se quita.
- Cada paso de más en un flujo es un hallazgo, con el número de clics de hoy y el mínimo posible.

**R10. Coherencia.**
- La misma cosa se ve y se llama igual en todas las pantallas: la misma acción usa el mismo texto (el botón «Pagar» produce el aviso «Pago realizado»), el mismo tipo de botón, la misma insignia de estado y el mismo formato de importes, porcentajes y fechas.
- Cada diferencia entre dos pantallas es un hallazgo, citando las dos.

**R11. Errores que se pueden resolver.** Un error dice qué ha pasado y qué hacer, en lenguaje llano; nunca un código interno ni un «inténtalo de nuevo» cuando reintentar no va a funcionar.

**R12. Reglas de diseño del proyecto.** Las del peer doc (colores por tokens semánticos, superficies, botones) mandan sobre cualquier preferencia general.

**R13. Todo en el idioma elegido.**
- Cada texto visible está en el idioma de la interfaz: títulos, botones, avisos, errores, ayudas, estados vacíos, el nombre accesible de los botones de icono, los PDF y los correos que la app genera. Un texto en otro idioma, un código interno en crudo (`ORDER_NOT_FOUND`, `admin.shop.title`) o un texto sin traducir es FALLO.
- Las fechas, horas, números, importes y porcentajes siguen el formato del idioma y la región del negocio, igual en todas las pantallas. Una fecha numérica que el usuario escribe dice en qué orden va (día, mes, año).
- Los nombres de idioma del selector se escriben en su propia lengua («Français», no «Francés»).
- Las frases no se rompen al traducir: concordancia, orden y plurales correctos («1 reserva», no «1 reservas»). Una frase mal montada delata texto pegado a trozos.
- El diseño aguanta el idioma con textos más largos: una etiqueta corta puede doblar o triplicar su longitud al traducirse. Nada se corta, se solapa ni se abrevia con «…» si el texto completo es necesario para entenderlo.

**R14. Legibilidad.**
- El texto de lectura (cuerpo, campos de formulario) mide al menos 16 px, y ningún texto con información baja de 12 px. *Porqué: por debajo de 16 px, el móvil amplía la página al tocar un campo y descoloca la pantalla.*
- Un bloque de texto corrido no pasa de 80 caracteres por línea (40 en chino, japonés o coreano).
- Con el navegador al 200 % de zoom, no se pierde contenido ni función.
- Si el usuario aumenta el interlineado a 1,5 veces la letra, el espacio entre párrafos a 2 veces, entre letras a 0,12 y entre palabras a 0,16, nada se corta ni se solapa.
- A 320 px de ancho todo se lee sin desplazamiento horizontal (R1).

**R15. Color en los dos modos.** Si el tema tiene modo claro y oscuro, R7 se cumple en los dos. Ningún texto queda del color de su fondo en un modo, y los colores de estado (error, aviso, éxito, información) mantienen su contraste con su texto.

**R16. Todo se usa con teclado.**
- Cada acción se puede hacer solo con teclado, en un orden de tabulación que sigue la lectura, sin quedar atrapado en ningún sitio.
- Los diálogos y menús se cierran con Esc y devuelven el foco al control que los abrió.
- Lo que se hace arrastrando (reordenar, deslizar, recortar) tiene también una forma de hacerse sin arrastrar.

**R17. Formularios.**
- Cada campo tiene una etiqueta visible que no desaparece al escribir: un texto de ejemplo dentro del campo no es una etiqueta.
- Un error se indica en el propio campo, con texto que dice qué falla y cómo arreglarlo; nunca solo con un borde rojo.
- Un dato que el usuario ya dio en el mismo proceso no se le vuelve a pedir.
- En el acceso, pegar la contraseña y el autocompletado del navegador funcionan, y ningún paso exige recordar o transcribir algo sin alternativa.

**R18. Avisos que se pueden leer.**
- Un aviso que desaparece solo da tiempo a leerlo entero. Si contiene algo que el usuario necesita (un error, un número, el siguiente paso), o se queda hasta que lo cierra o la misma información está también en la pantalla.
- Una ayuda que aparece al pasar el ratón o con el foco se puede cerrar con Esc, no desaparece al mover el puntero encima y se queda mientras el puntero o el foco sigan en su sitio.
- Un mismo hecho produce un solo aviso.

**R19. Sencilla, práctica y bonita.**
- Cada pantalla tiene una acción principal, y es la que más destaca; las demás se ven como secundarias. Dos acciones con el mismo peso visual en un mismo grupo es un hallazgo, salvo en una decisión del usuario (aceptar o rechazar), donde las dos opciones deben pesar lo mismo.
- La misma acción tiene el mismo tipo de botón en toda la app.
- Los espacios siguen una misma escala y los elementos se alinean entre sí; un hueco o un margen que no separa nada es un hallazgo (R2).
- La jerarquía se lee de un vistazo: el título manda, luego el contenido, luego los detalles.
- Cada elemento visible tiene una función. La decoración que no informa ni guía es una propuesta de eliminación.
- Un estado vacío dice qué hacer a continuación, con su botón.
- Para juzgar y proponer lo estético, carga `{{design_skill}}` y aplícala dentro del tema del negocio (sus colores y su tipografía mandan).

**R20. Se entiende sin ayuda.** Mira cada pantalla preguntándote: *«¿un cliente o un operador entiende esto sin ayuda, en su idioma y en móvil?»*. Una abreviatura, sigla o código sin explicar en la propia pantalla (p. ej. «F» y «FR» en una columna «Tipo», un estado técnico en inglés, un identificador interno) es FALLO de comprensión e idioma aunque la función vaya bien. Una aclaración que solo aparece al pasar el ratón (`title`, tooltip) no cuenta: no llega en móvil ni con teclado. Comprueba que el texto visible se traduce en todos los idiomas del sitio y que usa la palabra natural de cada uno (en castellano de España, «importe», no «monto»). Vale igual para los **correos**, asunto y cuerpo (HTML y texto): un «MEMBER», un «lost» o un «claim_accepted» en un aviso es el mismo FALLO. *Porqué: la función que no se entiende no existe para quien la usa; y lo que solo explica el ratón deja fuera a la mitad de los usuarios.*

## 2. Anchuras de prueba

- Móvil: 375×812. Además, 320 px de ancho para R1 y R14.
- Tableta: 768×1024.
- Escritorio: 1280×800.

Comprueba que la emulación sigue activa tras cada navegación: `innerWidth` debe valer el ancho pedido. Vuelve al tamaño normal al terminar.

## 3. Cómo medir

Pega estas funciones en la página (se pierden al navegar):

```js
window.__audit=()=>{const vis=e=>{const r=e.getBoundingClientRect(),s=getComputedStyle(e);return r.width>0&&r.height>0&&s.visibility!=='hidden'&&s.display!=='none'};
 const targets=[...document.querySelectorAll('main button,main a,main [role=button],main [role=checkbox],main input,main select')].filter(vis)
  .map(e=>{const r=e.getBoundingClientRect();return{t:(e.getAttribute('aria-label')||e.innerText||e.dataset.testid||e.tagName).trim().slice(0,30),w:Math.round(r.width),h:Math.round(r.height)}});
 const over=[...document.querySelectorAll('body *')].filter(e=>{const r=e.getBoundingClientRect();return r.right>innerWidth+1&&r.width>0&&getComputedStyle(e).position!=='fixed'}).slice(0,5)
  .map(e=>e.tagName+' r='+Math.round(e.getBoundingClientRect().right));
 const nested=[...document.querySelectorAll('a button, button a, a a, button button')].map(e=>(e.closest('a')?.getAttribute('href')||'')+' '+(e.innerText||e.getAttribute('aria-label')||'').trim().slice(0,20));
 return{ancho:innerWidth,scrollWidth:document.documentElement.scrollWidth,
  menos24:targets.filter(x=>x.w<24||x.h<24),menos44:targets.filter(x=>(x.w<44||x.h<44)&&x.w>=24&&x.h>=24).slice(0,15),
  desbordes:over,anidados:nested}};
window.__scroll=(re,mainSel)=>{const H=document.documentElement.scrollHeight;const cta=[...document.querySelectorAll('button,a')].find(b=>re.test(b.innerText.trim()));const r=cta?.getBoundingClientRect();
 const m=mainSel?document.querySelector(mainSel)?.getBoundingClientRect():null;
 return{pantallas:+(H/innerHeight).toFixed(1),accion:cta?.innerText.trim().slice(0,30),yAccion:r?Math.round(r.top+scrollY):null,
  accionVisible:r?(r.top+scrollY+r.height<=innerHeight):null,inicioContenido:m?Math.round(m.top+scrollY):null}};
```

- R1: `scrollWidth` frente a `ancho`, y `desbordes`.
- R4: `menos24` (grave) y `menos44` (en móvil). Descarta a mano los enlaces dentro de una frase.
- R5: `anidados`.
- R2 y R3: `__scroll(/acción principal/i, 'selector del primer elemento del contenido')`, con `inicioContenido` ≤ 200 en móvil y `accionVisible` = true.
- R6: tabula por la pantalla y mira el foco en una captura.

## 4. Contar clics y desplazamientos de un flujo

Recorre el flujo como un usuario nuevo y anota cada gesto: clic, tecla, desplazamiento, diálogo que interrumpe. Por ejemplo, de «veo un producto en la tienda» a «estoy en la pasarela de pago». Después escribe la versión mínima que cumpliría R2, R3, R8 y R9, y la diferencia.

## 5. Formato de las propuestas

Todas bloquean el cierre; el orden solo dice qué se arregla primero. Una tabla por flujo:

| Pantalla (ancho) | Regla | Medido hoy | Propuesta | Ahorro (clics / pantallas) |
|---|---|---|---|---|

Y una línea por flujo: «hoy N clics y M pantallas → con las propuestas N' y M'». Orden de prioridad:
1. R1, R4 por debajo de 24 px y R5.
2. Lo que ahorra pasos en flujos de dinero.
3. La coherencia (R10).
4. El resto.
