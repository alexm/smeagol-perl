<?xml version="1.0" encoding="UTF-8"?>
<xsl:stylesheet version="1.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform">
<xsl:template match="agenda">
<html><head></head><body>
<h1>Reserves del recurs</h1>
<table style="border:1px solid black; border-spacing: 1em">
<thead><tr><th>ID</th><th>Inici</th><th>Fi</th><th></th></tr></thead>
<tbody>
<xsl:apply-templates select="booking"/>
</tbody>
</table>

<hr/>
<a href="/resources">[Llista de recursos]</a> | <a href="#">[Nova reserva]</a>
</body></html>
</xsl:template>


<xsl:template match="booking">
<tr>
    <td><xsl:value-of select="id"/></td>
    <td><tt><xsl:apply-templates select="from"/></tt></td>
    <td><tt><xsl:apply-templates select="to"/></tt></td>
    <td><a href="#">[Detalls]</a> | <a href="#">[Modifica]</a> | <a href="#">[Esborra]</a></td>
</tr>
</xsl:template>


<xsl:template match="from|to">
<xsl:value-of select="year"/>-<xsl:value-of select="month"/>-<xsl:value-of select="day"/>
a les
<xsl:value-of select="hour"/>:<xsl:value-of select="minute"/> h
</xsl:template>

</xsl:stylesheet>
