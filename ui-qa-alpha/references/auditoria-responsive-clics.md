# Auditoría responsive, de clics y de desplazamientos

El usuario tiene que conseguir lo que vino a hacer con el menor esfuerzo posible, en cualquier pantalla, y ver una interfaz coherente de una pantalla a otra. Estas reglas son el listón: se miden, no se opinan. Un incumplimiento es un hallazgo con su medida; no hace falta justificarlo con nada más.

## Índice
1. Reglas
2. Anchuras de prueba
3. Cómo medir (fragmentos para el navegador)
4. Contar clics y desplazamientos de un flujo
5. Formato de las propuestas

## 1. Reglas

**R1. Sin desplazamiento horizontal.** A 320 px y a 375 px de ancho, la página no desplaza en horizontal (`scrollWidth` ≤ ancho de la ventana). Única excepción: una tabla de datos, un mapa o un diagrama que necesitan las dos dimensiones, y solo dentro de su propio contenedor desplazable, nunca la página entera. Aun así, en móvil se propone otra presentación (tarjetas, columnas plegables). Cualquier otro desplazamiento horizontal es FALLO. *Porqué: en móvil obliga a moverse en dos ejes para leer una sola cosa.*

**R2. Desplazamiento vertical mínimo.** Compacta: quita márgenes y rellenos que no separan nada, títulos con aire de sobra, bloques apilados que caben en una fila y avisos repetidos. En móvil (375×812), lo que va encima del contenido principal de la página (avisos, cabecera, título, filtros) no pasa de 200 px. La paginación va debajo de la lista, no encima. Los filtros y el buscador van en una fila. Una lista en móvil no ocupa una pantalla por elemento si el contenido cabe en dos columnas compactas. *Porqué: cada pantalla de más es un gesto más en cada visita.*

**R3. La acción principal se ve sin desplazarse.** En cada pantalla de un flujo, la acción principal (añadir, continuar, pagar, guardar) está dentro de la primera pantalla al cargar o fija en la parte inferior en móvil. *Porqué: si el usuario tiene que buscarla, el flujo se corta ahí.*

**R4. Objetivos táctiles.**
- Todo elemento pulsable mide al menos 44×44 px en móvil; la acción principal, 48 px de alto.
- Entre dos objetivos contiguos hay al menos 8 px.
- Por debajo de 24×24 px es FALLO grave. Entre 24 y 44 px en móvil, FALLO de usabilidad.
- Única excepción: un enlace dentro de una frase de texto.
- *Porqué: un dedo no es un puntero; los objetivos pequeños o pegados provocan toques equivocados.*

**R5. Ningún elemento interactivo dentro de otro.** Nada de `<button>` dentro de `<a>`, ni enlace dentro de enlace. *Porqué: el lector de pantalla y el teclado no saben cuál de los dos es la acción.*

**R6. Foco visible y no tapado.** Al recorrer con el tabulador, el elemento con foco se ve siempre y ninguna barra fija lo cubre.

**R7. Contraste.** El texto normal tiene un contraste de al menos 4,5:1 con su fondo; el texto grande y los bordes de controles, 3:1. El estado nunca se indica solo con color.

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

## 2. Anchuras de prueba

- Móvil: 375×812. Además, 320 px de ancho para R1.
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

Una tabla por flujo:

| Pantalla (ancho) | Regla | Medido hoy | Propuesta | Ahorro (clics / pantallas) |
|---|---|---|---|---|

Y una línea por flujo: «hoy N clics y M pantallas → con las propuestas N' y M'». Orden de prioridad:
1. R1, R4 por debajo de 24 px y R5.
2. Lo que ahorra pasos en flujos de dinero.
3. La coherencia (R10).
4. El resto.
