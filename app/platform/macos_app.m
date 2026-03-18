#import <AppKit/AppKit.h>
#import <math.h>
#import "merrow_freeform_canvas.h"

typedef struct {
    uint8_t r;
    uint8_t g;
    uint8_t b;
    uint8_t a;
} MerrowStudioColor;

typedef struct {
    double x;
    double y;
} MerrowStudioPoint;

typedef struct {
    double x;
    double y;
    double width;
    double height;
    double corner_radius;
    MerrowStudioColor fill;
    MerrowStudioColor stroke;
    float stroke_width;
    const char *title;
    double title_x;
    double title_y;
    float title_font_size;
    MerrowStudioColor title_color;
} MerrowStudioSubgraph;

typedef struct {
    uint32_t shape;
    double x;
    double y;
    double width;
    double height;
    MerrowStudioColor fill;
    MerrowStudioColor stroke;
    float stroke_width;
    const char *label;
    MerrowStudioColor label_color;
    float label_font_size;
    double max_text_width;
} MerrowStudioNode;

typedef struct {
    MerrowStudioPoint *points;
    size_t point_count;
    MerrowStudioColor color;
    float thickness;
    uint32_t line_style;
    uint8_t has_arrow;
    uint8_t has_source_arrow;
    MerrowStudioPoint target_from;
    MerrowStudioPoint target_tip;
    MerrowStudioPoint source_from;
    MerrowStudioPoint source_tip;
} MerrowStudioEdge;

typedef struct {
    const char *text;
    double x;
    double y;
    double half_w;
    double half_h;
    float font_size;
    MerrowStudioColor color;
} MerrowStudioEdgeLabel;

typedef struct {
    double width;
    double height;
    MerrowStudioColor background;
    MerrowStudioSubgraph *subgraphs;
    size_t subgraph_count;
    MerrowStudioNode *nodes;
    size_t node_count;
    MerrowStudioEdge *edges;
    size_t edge_count;
    MerrowStudioEdgeLabel *edge_labels;
    size_t edge_label_count;
} MerrowStudioScene;

extern const MerrowStudioScene *merrow_studio_create_default_scene(char *out_source_path, uint32_t out_source_path_len);
extern const MerrowStudioScene *merrow_studio_build_scene(const uint8_t *source_ptr, uint32_t source_len);
extern void merrow_studio_free_scene(const MerrowStudioScene *scene);
extern int merrow_studio_check_mermaid_syntax(const uint8_t *source_ptr, uint32_t source_len, char *out_message, uint32_t out_message_len);
extern int merrow_studio_render_preview_png(const uint8_t *source_ptr, uint32_t source_len, char *out_png_path, uint32_t out_png_path_len, char *out_message, uint32_t out_message_len);
extern int merrow_studio_export_diagram(const uint8_t *source_ptr, uint32_t source_len, const char *output_path_ptr, uint32_t format, double raster_scale, double layout_scale, char *out_message, uint32_t out_message_len);
extern char *merrow_studio_apply_command(const uint8_t *source_ptr, uint32_t source_len, const uint8_t *command_ptr, uint32_t command_len, const uint8_t *context_id_ptr, uint32_t context_id_len, char *out_context_id, uint32_t out_context_id_len, char *out_context_display, uint32_t out_context_display_len, char *out_message, uint32_t out_message_len);
extern char *merrow_studio_shuffle_diagram(const uint8_t *source_ptr, uint32_t source_len, char *out_message, uint32_t out_message_len);
extern const MerrowFreeformGraphSnapshot *merrow_studio_build_editable_graph(const uint8_t *source_ptr, uint32_t source_len, char *out_message, uint32_t out_message_len);
extern void merrow_studio_free_editable_graph(const MerrowFreeformGraphSnapshot *graph);
extern void merrow_studio_free_string(char *text);

static inline NSColor *MerrowNSColor(MerrowStudioColor color) {
    return [NSColor colorWithCalibratedRed:color.r / 255.0
                                     green:color.g / 255.0
                                      blue:color.b / 255.0
                                     alpha:color.a / 255.0];
}

static NSString *MerrowStudioUntitledSource(void) {
    return @"flowchart TD\n    Start([Start])\n    Step[Edit Mermaid here]\n    Start --> Step\n";
}

static void MerrowSetAllowedFileTypes(NSSavePanel *panel, NSArray<NSString *> *extensions) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    panel.allowedFileTypes = extensions;
#pragma clang diagnostic pop
}

static NSBezierPath *MerrowPolygonPath(const CGPoint *points, NSUInteger count) {
    NSBezierPath *path = [NSBezierPath bezierPath];
    if (count == 0) return path;
    [path moveToPoint:points[0]];
    for (NSUInteger idx = 1; idx < count; idx += 1) {
        [path lineToPoint:points[idx]];
    }
    [path closePath];
    return path;
}

static NSBezierPath *MerrowNodePath(const MerrowStudioNode *node) {
    const CGFloat x = (CGFloat)(node->x - node->width / 2.0);
    const CGFloat y = (CGFloat)(node->y - node->height / 2.0);
    const CGFloat w = (CGFloat)node->width;
    const CGFloat h = (CGFloat)node->height;
    const CGFloat cx = (CGFloat)node->x;
    const CGFloat cy = (CGFloat)node->y;
    const CGFloat hw = w / 2.0;
    const CGFloat hh = h / 2.0;

    switch (node->shape) {
        case 0:
            return [NSBezierPath bezierPathWithRect:NSMakeRect(x, y, w, h)];
        case 1:
            return [NSBezierPath bezierPathWithRoundedRect:NSMakeRect(x, y, w, h) xRadius:MIN(MIN(hw, hh), 12.0) yRadius:MIN(MIN(hw, hh), 12.0)];
        case 2: {
            CGPoint points[4] = {
                { cx, cy - hh },
                { cx + hw, cy },
                { cx, cy + hh },
                { cx - hw, cy },
            };
            return MerrowPolygonPath(points, 4);
        }
        case 3:
            return [NSBezierPath bezierPathWithOvalInRect:NSMakeRect(x, y, w, h)];
        case 4: {
            const CGFloat inset = hw * 0.35;
            CGPoint points[6] = {
                { cx - hw + inset, cy - hh },
                { cx + hw - inset, cy - hh },
                { cx + hw, cy },
                { cx + hw - inset, cy + hh },
                { cx - hw + inset, cy + hh },
                { cx - hw, cy },
            };
            return MerrowPolygonPath(points, 6);
        }
        case 5:
        case 6:
            return [NSBezierPath bezierPathWithRoundedRect:NSMakeRect(x, y, w, h) xRadius:hh yRadius:hh];
        case 7: {
            const CGFloat inset = hw * 0.25;
            CGPoint points[4] = {
                { cx - hw + inset, cy - hh },
                { cx + hw - inset, cy - hh },
                { cx + hw, cy + hh },
                { cx - hw, cy + hh },
            };
            return MerrowPolygonPath(points, 4);
        }
        case 8: {
            const CGFloat inset = hw * 0.25;
            CGPoint points[4] = {
                { cx - hw, cy - hh },
                { cx + hw, cy - hh },
                { cx + hw - inset, cy + hh },
                { cx - hw + inset, cy + hh },
            };
            return MerrowPolygonPath(points, 4);
        }
        case 9: {
            const CGFloat slant = hw * 0.25;
            CGPoint points[4] = {
                { cx - hw + slant, cy - hh },
                { cx + hw + slant, cy - hh },
                { cx + hw - slant, cy + hh },
                { cx - hw - slant, cy + hh },
            };
            return MerrowPolygonPath(points, 4);
        }
        case 10: {
            const CGFloat slant = hw * 0.25;
            CGPoint points[4] = {
                { cx - hw - slant, cy - hh },
                { cx + hw - slant, cy - hh },
                { cx + hw + slant, cy + hh },
                { cx - hw + slant, cy + hh },
            };
            return MerrowPolygonPath(points, 4);
        }
        case 11:
            return [NSBezierPath bezierPathWithRect:NSMakeRect(x, y, w, h)];
        default:
            return [NSBezierPath bezierPathWithRect:NSMakeRect(x, y, w, h)];
    }
}

static void MerrowDrawArrow(CGPoint from, CGPoint tip, NSColor *color) {
    const CGFloat dx = tip.x - from.x;
    const CGFloat dy = tip.y - from.y;
    const CGFloat len = hypot(dx, dy);
    if (len < 0.001) return;

    const CGFloat ux = dx / len;
    const CGFloat uy = dy / len;
    const CGFloat px = -uy;
    const CGFloat py = ux;
    const CGFloat size = 10.0;
    const CGFloat halfWidth = size * 0.45;

    CGPoint points[3] = {
        tip,
        { tip.x - ux * size + px * halfWidth, tip.y - uy * size + py * halfWidth },
        { tip.x - ux * size - px * halfWidth, tip.y - uy * size - py * halfWidth },
    };

    [color setFill];
    [MerrowPolygonPath(points, 3) fill];
}

@interface MerrowSceneRenderer : NSObject
@property (nonatomic, assign) const MerrowStudioScene *scene;
@property (nonatomic, strong) NSImage *previewImage;
@property (nonatomic, copy) NSString *previewImagePath;
@property (nonatomic, assign) CGFloat zoom;
@property (nonatomic, assign) CGPoint pan;
@end

@interface MerrowViewportView : NSView
@property (nonatomic, weak) MerrowSceneRenderer *viewportRenderer;
@property (nonatomic, assign) NSPoint lastDragPoint;
@property (nonatomic, assign) BOOL dragging;
@property (nonatomic, strong) NSMagnificationGestureRecognizer *magnifyRecognizer;
@end

@implementation MerrowSceneRenderer

- (void)discardPreviewImage {
    self.previewImage = nil;
    if (self.previewImagePath.length > 0) {
        [[NSFileManager defaultManager] removeItemAtPath:self.previewImagePath error:nil];
        self.previewImagePath = nil;
    }
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _zoom = 1.0;
        _pan = CGPointZero;
    }
    return self;
}

- (void)dealloc {
    if (_scene) {
        merrow_studio_free_scene(_scene);
    }
    [self discardPreviewImage];
}

- (void)replaceScene:(const MerrowStudioScene *)scene {
    if (_scene) {
        merrow_studio_free_scene(_scene);
    }
    _scene = scene;
    [self discardPreviewImage];
}

- (void)replacePreviewImage:(NSImage *)image path:(NSString *)path {
    if (_scene) {
        merrow_studio_free_scene(_scene);
        _scene = NULL;
    }
    [self discardPreviewImage];
    self.previewImage = image;
    self.previewImagePath = [path copy];
}

- (void)resetView {
    self.zoom = 1.0;
    self.pan = CGPointZero;
}

- (void)adjustPanByViewDeltaX:(CGFloat)deltaX deltaY:(CGFloat)deltaY {
    self.pan = CGPointMake(self.pan.x + deltaX, self.pan.y + deltaY);
}

- (void)adjustZoomByFactor:(CGFloat)factor {
    const CGFloat nextZoom = self.zoom * factor;
    self.zoom = fmax(0.25, fmin(nextZoom, 8.0));
}

- (NSDictionary<NSAttributedStringKey, id> *)attributesWithFontSize:(CGFloat)fontSize color:(NSColor *)color {
    NSFont *font = [NSFont fontWithName:@"Lato" size:fontSize];
    if (!font) font = [NSFont systemFontOfSize:fontSize weight:NSFontWeightRegular];
    NSMutableParagraphStyle *style = [[NSMutableParagraphStyle alloc] init];
    style.alignment = NSTextAlignmentCenter;
    style.lineBreakMode = NSLineBreakByWordWrapping;
    return @{ NSFontAttributeName: font, NSForegroundColorAttributeName: color, NSParagraphStyleAttributeName: style };
}

- (NSRect)textRectForNode:(const MerrowStudioNode *)node {
    const CGFloat outerX = (CGFloat)(node->x - node->width / 2.0);
    const CGFloat outerY = (CGFloat)(node->y - node->height / 2.0);
    CGFloat insetX = 10.0;
    CGFloat insetY = 8.0;

    switch (node->shape) {
        case 2:
            insetX = MAX(18.0, node->width * 0.24);
            insetY = MAX(12.0, node->height * 0.20);
            break;
        case 3:
            insetX = MAX(16.0, node->width * 0.18);
            insetY = MAX(12.0, node->height * 0.18);
            break;
        case 4:
            insetX = MAX(18.0, node->width * 0.18);
            insetY = 10.0;
            break;
        case 5:
            insetX = 12.0;
            insetY = MAX(14.0, node->height * 0.22);
            break;
        case 6:
            insetX = MAX(16.0, node->height * 0.28);
            insetY = 8.0;
            break;
        case 7:
        case 8:
        case 9:
        case 10:
            insetX = MAX(16.0, node->width * 0.16);
            insetY = 10.0;
            break;
        case 11:
            insetX = MAX(18.0, node->width * 0.18);
            insetY = 8.0;
            break;
        default:
            break;
    }

    const CGFloat maxWidth = MAX(node->width - insetX * 2.0, 24.0);
    const CGFloat maxHeight = MAX(node->height - insetY * 2.0, 18.0);
    return NSMakeRect(node->x - maxWidth / 2.0, node->y - maxHeight / 2.0, maxWidth, maxHeight);
}

- (void)drawCenteredText:(NSString *)text inRect:(NSRect)rect fontSize:(CGFloat)fontSize color:(NSColor *)color {
    if (text.length == 0) return;

    CGFloat fittedFontSize = fontSize;
    NSDictionary *attrs = nil;
    NSRect measured = NSZeroRect;

    while (fittedFontSize >= 8.0) {
        attrs = [self attributesWithFontSize:fittedFontSize color:color];
        measured = [text boundingRectWithSize:rect.size
                                      options:NSStringDrawingUsesLineFragmentOrigin | NSStringDrawingUsesFontLeading
                                   attributes:attrs];
        if (measured.size.height <= rect.size.height + 0.5) {
            break;
        }
        fittedFontSize -= 0.5;
    }

    NSRect drawRect = rect;
    drawRect.origin.y = rect.origin.y + floor((rect.size.height - measured.size.height) * 0.5);
    drawRect.size.height = MIN(rect.size.height, ceil(measured.size.height));
    [text drawWithRect:drawRect options:NSStringDrawingUsesLineFragmentOrigin | NSStringDrawingUsesFontLeading attributes:attrs];
}

- (void)drawCylinderNode:(const MerrowStudioNode *)node {
    const CGFloat hw = (CGFloat)(node->width / 2.0);
    const CGFloat hh = (CGFloat)(node->height / 2.0);
    const CGFloat x = (CGFloat)(node->x - hw);
    const CGFloat y = (CGFloat)(node->y - hh);
    const CGFloat capH = MIN(MAX(hh * 0.30, 8.0), 14.0);
    NSColor *fillColor = [MerrowNSColor(node->fill) colorUsingColorSpace:[NSColorSpace deviceRGBColorSpace]];
    NSColor *strokeColor = [MerrowNSColor(node->stroke) colorUsingColorSpace:[NSColorSpace deviceRGBColorSpace]];

    NSRect bodyRect = NSMakeRect(x, y + capH, node->width, node->height - capH * 2.0);
    NSRect topOvalRect = NSMakeRect(x, y, node->width, capH * 2.0);
    NSRect bottomOvalRect = NSMakeRect(x, y + node->height - capH * 2.0, node->width, capH * 2.0);

    [fillColor setFill];
    NSRectFill(bodyRect);
    [[NSBezierPath bezierPathWithOvalInRect:bottomOvalRect] fill];
    [[NSBezierPath bezierPathWithOvalInRect:topOvalRect] fill];

    [strokeColor setStroke];
    NSBezierPath *topOval = [NSBezierPath bezierPathWithOvalInRect:topOvalRect];
    topOval.lineWidth = node->stroke_width;
    [topOval stroke];

    NSBezierPath *sides = [NSBezierPath bezierPath];
    [sides moveToPoint:CGPointMake(x, y + capH)];
    [sides lineToPoint:CGPointMake(x, y + node->height - capH)];
    [sides moveToPoint:CGPointMake(x + node->width, y + capH)];
    [sides lineToPoint:CGPointMake(x + node->width, y + node->height - capH)];
    sides.lineWidth = node->stroke_width;
    [sides stroke];

    NSBezierPath *bottomFrontArc = [NSBezierPath bezierPath];
    const CGFloat bottomY = y + node->height - capH;
    const CGFloat leftX = x;
    const CGFloat rightX = x + node->width;
    [bottomFrontArc moveToPoint:CGPointMake(leftX, bottomY)];
    [bottomFrontArc curveToPoint:CGPointMake(rightX, bottomY)
                   controlPoint1:CGPointMake(leftX + node->width * 0.22, bottomY + capH)
                   controlPoint2:CGPointMake(rightX - node->width * 0.22, bottomY + capH)];
    bottomFrontArc.lineWidth = node->stroke_width;
    [bottomFrontArc stroke];
}

- (void)drawNode:(const MerrowStudioNode *)node {
    if (node->shape == 5) {
        [self drawCylinderNode:node];
    } else {
        NSBezierPath *path = MerrowNodePath(node);
        [[MerrowNSColor(node->fill) colorUsingColorSpace:[NSColorSpace deviceRGBColorSpace]] setFill];
        [[MerrowNSColor(node->stroke) colorUsingColorSpace:[NSColorSpace deviceRGBColorSpace]] setStroke];
        path.lineWidth = node->stroke_width;
        [path fill];
        [path stroke];
    }

    if (node->shape == 11) {
        const CGFloat hw = (CGFloat)(node->width / 2.0);
        const CGFloat hh = (CGFloat)(node->height / 2.0);
        const CGFloat inset = MAX(hw * 0.15, 6.0);
        NSBezierPath *left = [NSBezierPath bezierPath];
        [left moveToPoint:CGPointMake(node->x - hw + inset, node->y - hh)];
        [left lineToPoint:CGPointMake(node->x - hw + inset, node->y + hh)];
        left.lineWidth = node->stroke_width;
        [left stroke];
        NSBezierPath *right = [NSBezierPath bezierPath];
        [right moveToPoint:CGPointMake(node->x + hw - inset, node->y - hh)];
        [right lineToPoint:CGPointMake(node->x + hw - inset, node->y + hh)];
        right.lineWidth = node->stroke_width;
        [right stroke];
    }

    if (node->label) {
        NSString *text = [NSString stringWithUTF8String:node->label];
        [self drawCenteredText:text inRect:[self textRectForNode:node] fontSize:node->label_font_size color:MerrowNSColor(node->label_color)];
    }
}

- (void)drawEdge:(const MerrowStudioEdge *)edge {
    if (edge->point_count < 2) return;

    NSBezierPath *path = [NSBezierPath bezierPath];
    [path moveToPoint:CGPointMake(edge->points[0].x, edge->points[0].y)];
    for (size_t idx = 1; idx < edge->point_count; idx += 1) {
        [path lineToPoint:CGPointMake(edge->points[idx].x, edge->points[idx].y)];
    }
    path.lineJoinStyle = NSLineJoinStyleRound;
    path.lineCapStyle = NSLineCapStyleRound;
    path.lineWidth = edge->thickness;

    CGFloat pattern[2] = { 0.0, 0.0 };
    if (edge->line_style == 1) {
        pattern[0] = 10.0;
        pattern[1] = 6.0;
        [path setLineDash:pattern count:2 phase:0.0];
    } else if (edge->line_style == 2) {
        pattern[0] = 4.0;
        pattern[1] = 4.0;
        [path setLineDash:pattern count:2 phase:0.0];
    }

    NSColor *stroke = MerrowNSColor(edge->color);
    [stroke setStroke];
    [path stroke];

    if (edge->has_arrow) {
        MerrowDrawArrow(CGPointMake(edge->target_from.x, edge->target_from.y), CGPointMake(edge->target_tip.x, edge->target_tip.y), stroke);
    }
    if (edge->has_source_arrow) {
        MerrowDrawArrow(CGPointMake(edge->source_from.x, edge->source_from.y), CGPointMake(edge->source_tip.x, edge->source_tip.y), stroke);
    }
}

- (void)drawInView:(NSView *)view {
    const MerrowStudioScene *scene = self.scene;
    NSImage *previewImage = self.previewImage;
    [[NSColor colorWithCalibratedRed:0.93 green:0.94 blue:0.96 alpha:1.0] setFill];
    NSRectFill(view.bounds);

    if (!scene && !previewImage) return;

    const CGFloat contentWidth = scene ? scene->width : previewImage.size.width;
    const CGFloat contentHeight = scene ? scene->height : previewImage.size.height;

    const CGFloat availableWidth = MAX(view.bounds.size.width - 48.0, 64.0);
    const CGFloat availableHeight = MAX(view.bounds.size.height - 48.0, 64.0);
    const CGFloat fitScaleX = contentWidth > 0.0 ? availableWidth / contentWidth : 1.0;
    const CGFloat fitScaleY = contentHeight > 0.0 ? availableHeight / contentHeight : 1.0;
    const CGFloat fitScale = MAX(MIN(fitScaleX, fitScaleY), 0.01);
    const CGFloat totalScale = fitScale * self.zoom;

    [NSGraphicsContext saveGraphicsState];
    NSAffineTransform *transform = [NSAffineTransform transform];
    [transform translateXBy:view.bounds.size.width / 2.0 + self.pan.x yBy:view.bounds.size.height / 2.0 + self.pan.y];
    [transform scaleBy:totalScale];
    [transform translateXBy:-contentWidth / 2.0 yBy:-contentHeight / 2.0];
    [transform concat];

    if (!scene && previewImage) {
        [previewImage drawInRect:NSMakeRect(0.0, 0.0, contentWidth, contentHeight)
                        fromRect:NSZeroRect
                       operation:NSCompositingOperationSourceOver
                        fraction:1.0
                  respectFlipped:YES
                           hints:@{ NSImageHintInterpolation : @(NSImageInterpolationHigh) }];
        [NSGraphicsContext restoreGraphicsState];
        return;
    }

    [[MerrowNSColor(scene->background) colorUsingColorSpace:[NSColorSpace deviceRGBColorSpace]] setFill];
    NSRectFill(NSMakeRect(0.0, 0.0, scene->width, scene->height));

    for (size_t idx = 0; idx < scene->subgraph_count; idx += 1) {
        const MerrowStudioSubgraph *subgraph = &scene->subgraphs[idx];
        NSBezierPath *path = [NSBezierPath bezierPathWithRoundedRect:NSMakeRect(subgraph->x, subgraph->y, subgraph->width, subgraph->height) xRadius:subgraph->corner_radius yRadius:subgraph->corner_radius];
        path.lineWidth = subgraph->stroke_width;
        [MerrowNSColor(subgraph->fill) setFill];
        [MerrowNSColor(subgraph->stroke) setStroke];
        [path fill];
        [path stroke];

        if (subgraph->title) {
            NSString *title = [NSString stringWithUTF8String:subgraph->title];
            NSDictionary *attrs = @{ NSFontAttributeName: [NSFont systemFontOfSize:subgraph->title_font_size weight:NSFontWeightSemibold], NSForegroundColorAttributeName: MerrowNSColor(subgraph->title_color) };
            [title drawAtPoint:CGPointMake(subgraph->title_x, subgraph->title_y) withAttributes:attrs];
        }
    }

    for (size_t idx = 0; idx < scene->edge_count; idx += 1) {
        [self drawEdge:&scene->edges[idx]];
    }

    for (size_t idx = 0; idx < scene->node_count; idx += 1) {
        [self drawNode:&scene->nodes[idx]];
    }

    for (size_t idx = 0; idx < scene->edge_label_count; idx += 1) {
        const MerrowStudioEdgeLabel *label = &scene->edge_labels[idx];
        NSRect labelRect = NSMakeRect(label->x - label->half_w, label->y - label->half_h, label->half_w * 2.0, label->half_h * 2.0);
        [[NSColor colorWithCalibratedWhite:1.0 alpha:0.92] setFill];
        [[NSBezierPath bezierPathWithRoundedRect:labelRect xRadius:4.0 yRadius:4.0] fill];
        if (label->text) {
            NSString *text = [NSString stringWithUTF8String:label->text];
            [self drawCenteredText:text inRect:labelRect fontSize:label->font_size color:MerrowNSColor(label->color)];
        }
    }

    [NSGraphicsContext restoreGraphicsState];
}

@end

@implementation MerrowViewportView

- (instancetype)initWithFrame:(NSRect)frameRect {
    self = [super initWithFrame:frameRect];
    if (self) {
        self.wantsLayer = YES;
        self.layer.backgroundColor = [NSColor colorWithCalibratedRed:0.93 green:0.94 blue:0.96 alpha:1.0].CGColor;
        _magnifyRecognizer = [[NSMagnificationGestureRecognizer alloc] initWithTarget:self action:@selector(handleMagnifyGesture:)];
        [self addGestureRecognizer:_magnifyRecognizer];
    }
    return self;
}

- (BOOL)isFlipped {
    return YES;
}

- (BOOL)acceptsFirstResponder {
    return YES;
}

- (void)drawRect:(NSRect)dirtyRect {
    (void)dirtyRect;
    [self.viewportRenderer drawInView:self];
}

- (void)mouseDown:(NSEvent *)event {
    self.dragging = YES;
    self.lastDragPoint = [self convertPoint:event.locationInWindow fromView:nil];
}

- (void)mouseDragged:(NSEvent *)event {
    if (!self.dragging || !self.viewportRenderer) return;
    NSPoint point = [self convertPoint:event.locationInWindow fromView:nil];
    CGFloat dx = point.x - self.lastDragPoint.x;
    CGFloat dy = point.y - self.lastDragPoint.y;
    [self.viewportRenderer adjustPanByViewDeltaX:dx deltaY:dy];
    self.lastDragPoint = point;
    [self setNeedsDisplay:YES];
}

- (void)mouseUp:(NSEvent *)event {
    (void)event;
    self.dragging = NO;
}

- (void)scrollWheel:(NSEvent *)event {
    if (!self.viewportRenderer) {
        [super scrollWheel:event];
        return;
    }

    if (fabs(event.scrollingDeltaY) >= fabs(event.scrollingDeltaX)) {
        const CGFloat factor = pow(1.01, -event.scrollingDeltaY);
        [self.viewportRenderer adjustZoomByFactor:factor];
    } else {
        [self.viewportRenderer adjustPanByViewDeltaX:-event.scrollingDeltaX deltaY:event.scrollingDeltaY];
    }
    [self setNeedsDisplay:YES];
}

- (void)magnifyWithEvent:(NSEvent *)event {
    if (!self.viewportRenderer) return;
    [self.viewportRenderer adjustZoomByFactor:(1.0 + event.magnification)];
    [self setNeedsDisplay:YES];
}

- (void)handleMagnifyGesture:(NSMagnificationGestureRecognizer *)recognizer {
    if (!self.viewportRenderer) return;
    if (recognizer.state == NSGestureRecognizerStateBegan || recognizer.state == NSGestureRecognizerStateChanged) {
        [self.viewportRenderer adjustZoomByFactor:(1.0 + recognizer.magnification)];
        recognizer.magnification = 0.0;
        [self setNeedsDisplay:YES];
    }
}

- (void)smartMagnifyWithEvent:(NSEvent *)event {
    (void)event;
    if (!self.viewportRenderer) return;
    [self.viewportRenderer resetView];
    [self setNeedsDisplay:YES];
}

@end

@interface MerrowEditorTextView : NSTextView
@end

@implementation MerrowEditorTextView

- (BOOL)acceptsFirstMouse:(NSEvent *)event {
    (void)event;
    return YES;
}

- (void)scrollWheel:(NSEvent *)event {
    NSScrollView *scrollView = self.enclosingScrollView;
    if (scrollView) {
        [scrollView scrollWheel:event];
        return;
    }
    [super scrollWheel:event];
}

@end

@interface MerrowStudioAppDelegate : NSObject <NSApplicationDelegate, NSSplitViewDelegate, NSWindowDelegate, NSTextViewDelegate, MerrowFreeformCanvasComponentDelegate>
@property (nonatomic, strong) NSWindow *window;
@property (nonatomic, strong) NSSplitView *splitView;
@property (nonatomic, strong) NSTextField *statusLabel;
@property (nonatomic, strong) NSTextField *contextLabel;
@property (nonatomic, strong) NSTextField *commandField;
@property (nonatomic, strong) NSButton *commandButton;
@property (nonatomic, strong) MerrowSceneRenderer *viewerRenderer;
@property (nonatomic, strong) MerrowViewportView *viewerView;
@property (nonatomic, strong) NSView *viewerPane;
@property (nonatomic, strong) NSView *viewerPaneContentHost;
@property (nonatomic, strong) NSView *editorPane;
@property (nonatomic, strong) NSView *editorPaneContentHost;
@property (nonatomic, strong) NSScrollView *editorScrollView;
@property (nonatomic, strong) NSScrollView *freeformToolsScrollView;
@property (nonatomic, strong) NSScrollView *sequenceToolsScrollView;
@property (nonatomic, strong) MerrowFreeformCanvasComponent *freeformCanvasComponent;
@property (nonatomic, strong) NSTextView *editorTextView;
@property (nonatomic, strong) NSTextField *viewerPaneTitleLabel;
@property (nonatomic, strong) NSTextField *viewerPaneSubtitleLabel;
@property (nonatomic, strong) NSTextField *editorPaneTitleLabel;
@property (nonatomic, strong) NSTextField *editorPaneSubtitleLabel;
@property (nonatomic, strong) NSTextField *freeformSelectionLabel;
@property (nonatomic, strong) NSTextField *freeformCreateStatusLabel;
@property (nonatomic, strong) NSColorWell *freeformCanvasBackgroundColorWell;
@property (nonatomic, strong) NSSlider *freeformCanvasBackgroundOpacitySlider;
@property (nonatomic, strong) NSTextField *freeformCanvasBackgroundOpacityValueLabel;
@property (nonatomic, strong) NSTextField *freeformNodeLabelField;
@property (nonatomic, strong) NSTextField *freeformWidthField;
@property (nonatomic, strong) NSTextField *freeformHeightField;
@property (nonatomic, strong) NSPopUpButton *freeformShapePopup;
@property (nonatomic, strong) NSButton *freeformAddShapeButton;
@property (nonatomic, strong) NSButton *freeformAddGroupButton;
@property (nonatomic, strong) NSButton *freeformCancelCreateButton;
@property (nonatomic, strong) NSColorWell *freeformFillColorWell;
@property (nonatomic, strong) NSColorWell *freeformStrokeColorWell;
@property (nonatomic, strong) NSSlider *freeformStrokeWidthSlider;
@property (nonatomic, strong) NSTextField *freeformStrokeWidthValueLabel;
@property (nonatomic, strong) NSTextField *freeformEdgeLabelField;
@property (nonatomic, strong) NSColorWell *freeformEdgeColorWell;
@property (nonatomic, strong) NSSlider *freeformEdgeThicknessSlider;
@property (nonatomic, strong) NSTextField *freeformEdgeThicknessValueLabel;
@property (nonatomic, strong) NSPopUpButton *freeformEdgePatternPopup;
@property (nonatomic, strong) NSPopUpButton *freeformEdgeArrowPopup;
@property (nonatomic, strong) NSPopUpButton *freeformConnectorSourcePopup;
@property (nonatomic, strong) NSPopUpButton *freeformConnectorTargetPopup;
@property (nonatomic, strong) NSButton *freeformAddConnectorButton;
@property (nonatomic, strong) NSTextField *sequenceSelectionLabel;
@property (nonatomic, strong) NSColorWell *sequenceCanvasBackgroundColorWell;
@property (nonatomic, strong) NSSlider *sequenceCanvasBackgroundOpacitySlider;
@property (nonatomic, strong) NSTextField *sequenceCanvasBackgroundOpacityValueLabel;
@property (nonatomic, strong) NSTextField *sequenceElementLabelField;
@property (nonatomic, strong) NSTextField *sequenceWidthField;
@property (nonatomic, strong) NSTextField *sequenceHeightField;
@property (nonatomic, strong) NSColorWell *sequenceFillColorWell;
@property (nonatomic, strong) NSColorWell *sequenceStrokeColorWell;
@property (nonatomic, strong) NSSlider *sequenceStrokeWidthSlider;
@property (nonatomic, strong) NSTextField *sequenceStrokeWidthValueLabel;
@property (nonatomic, strong) NSTextField *sequenceMessageLabelField;
@property (nonatomic, strong) NSColorWell *sequenceMessageColorWell;
@property (nonatomic, strong) NSSlider *sequenceMessageThicknessSlider;
@property (nonatomic, strong) NSTextField *sequenceMessageThicknessValueLabel;
@property (nonatomic, strong) NSPopUpButton *sequenceMessagePatternPopup;
@property (nonatomic, strong) NSPopUpButton *sequenceMessageArrowPopup;
@property (nonatomic, strong) NSMenuItem *mermaidModeMenuItem;
@property (nonatomic, strong) NSMenuItem *freeformModeMenuItem;
@property (nonatomic, copy) NSString *currentSourcePath;
@property (nonatomic, assign) BOOL currentDocumentIsFreeform;
@property (nonatomic, assign) BOOL isApplyingHighlighting;
@property (nonatomic, assign) BOOL isSynchronizingEditor;
@property (nonatomic, assign) BOOL freeformModeEnabled;
@property (nonatomic, assign) NSUInteger editorGeneration;
@property (nonatomic, strong) dispatch_queue_t editorWorkQueue;
@property (nonatomic, copy) NSString *currentCommandContextId;
@property (nonatomic, copy) NSString *currentCommandContextDisplay;
@end

@implementation MerrowStudioAppDelegate

- (BOOL)validateMenuItem:(NSMenuItem *)menuItem {
    SEL action = menuItem.action;
    if (action == @selector(resetFreeformToMermaid:)) {
        return self.freeformModeEnabled || self.currentDocumentIsFreeform;
    }
    return YES;
}

- (NSColor *)editorColorForWord:(NSString *)word {
    static NSSet<NSString *> *keywords;
    static NSSet<NSString *> *directions;
    if (keywords == nil || directions == nil) {
        keywords = [NSSet setWithArray:@[@"graph", @"flowchart", @"subgraph", @"end", @"classDef", @"class", @"style", @"click", @"linkStyle"]];
        directions = [NSSet setWithArray:@[@"TD", @"TB", @"LR", @"RL", @"BT"]];
    }

    if ([keywords containsObject:word]) {
        return [NSColor colorWithRed:0.98 green:0.67 blue:0.33 alpha:1.0];
    }
    if ([directions containsObject:word]) {
        return [NSColor colorWithRed:0.45 green:0.78 blue:0.98 alpha:1.0];
    }
    return [NSColor colorWithRed:0.86 green:0.88 blue:0.91 alpha:1.0];
}

- (NSArray<NSDictionary *> *)segmentsForLine:(NSString *)line {
    NSMutableArray<NSDictionary *> *segments = [NSMutableArray array];
    if (line.length == 0) {
        return segments;
    }

    if ([line hasPrefix:@"%%"]) {
        [segments addObject:@{ @"text": line, @"color": [NSColor colorWithRed:0.48 green:0.66 blue:0.52 alpha:1.0] }];
        return segments;
    }

    NSArray<NSString *> *arrows = @[ @"<==>", @"<-.->", @"<-->", @"==>", @"-.->", @"-->", @"---", @"<:::", @":::" ];
    NSCharacterSet *wordSet = [NSCharacterSet characterSetWithCharactersInString:@"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_"];

    NSUInteger idx = 0;
    while (idx < line.length) {
        NSString *remaining = [line substringFromIndex:idx];
        BOOL matchedArrow = NO;
        for (NSString *arrow in arrows) {
            if ([remaining hasPrefix:arrow]) {
                [segments addObject:@{ @"text": arrow, @"color": [NSColor colorWithRed:0.96 green:0.43 blue:0.43 alpha:1.0] }];
                idx += arrow.length;
                matchedArrow = YES;
                break;
            }
        }
        if (matchedArrow) continue;

        unichar c = [line characterAtIndex:idx];
        if (c == '"') {
            NSUInteger start = idx;
            idx += 1;
            while (idx < line.length) {
                unichar q = [line characterAtIndex:idx];
                idx += 1;
                if (q == '"') break;
            }
            NSString *chunk = [line substringWithRange:NSMakeRange(start, idx - start)];
            [segments addObject:@{ @"text": chunk, @"color": [NSColor colorWithRed:0.62 green:0.83 blue:0.57 alpha:1.0] }];
            continue;
        }

        if ([[NSCharacterSet whitespaceCharacterSet] characterIsMember:c]) {
            NSUInteger start = idx;
            while (idx < line.length && [[NSCharacterSet whitespaceCharacterSet] characterIsMember:[line characterAtIndex:idx]]) {
                idx += 1;
            }
            [segments addObject:@{ @"text": [line substringWithRange:NSMakeRange(start, idx - start)], @"color": [NSColor clearColor] }];
            continue;
        }

        if ([wordSet characterIsMember:c]) {
            NSUInteger start = idx;
            while (idx < line.length && [wordSet characterIsMember:[line characterAtIndex:idx]]) {
                idx += 1;
            }
            NSString *word = [line substringWithRange:NSMakeRange(start, idx - start)];
            [segments addObject:@{ @"text": word, @"color": [self editorColorForWord:word] }];
            continue;
        }

        NSString *chunk = [line substringWithRange:NSMakeRange(idx, 1)];
        [segments addObject:@{ @"text": chunk, @"color": [NSColor colorWithRed:0.73 green:0.75 blue:0.80 alpha:1.0] }];
        idx += 1;
    }

    return segments;
}

- (NSDictionary<NSAttributedStringKey, id> *)baseEditorAttributes {
    NSFont *font = [NSFont fontWithName:@"Menlo-Regular" size:14.0];
    if (!font) {
        font = [NSFont monospacedSystemFontOfSize:14.0 weight:NSFontWeightRegular];
    }
    NSMutableParagraphStyle *style = [[NSMutableParagraphStyle alloc] init];
    style.lineHeightMultiple = 1.14;
    return @{
        NSFontAttributeName: font,
        NSForegroundColorAttributeName: [NSColor colorWithRed:0.86 green:0.88 blue:0.91 alpha:1.0],
        NSParagraphStyleAttributeName: style,
    };
}

- (void)applySyntaxHighlighting {
    if (!self.editorTextView) return;

    NSTextStorage *storage = self.editorTextView.textStorage;
    NSString *source = self.editorTextView.string ?: @"";
    if (storage.length == 0) {
        self.editorTextView.typingAttributes = [self baseEditorAttributes];
        return;
    }

    NSDictionary<NSAttributedStringKey, id> *baseAttrs = [self baseEditorAttributes];
    NSRange fullRange = NSMakeRange(0, storage.length);

    self.isApplyingHighlighting = YES;
    [storage beginEditing];
    [storage setAttributes:baseAttrs range:fullRange];

    [source enumerateSubstringsInRange:NSMakeRange(0, source.length)
                               options:NSStringEnumerationByLines
                            usingBlock:^(NSString *line, NSRange lineRange, NSRange enclosingRange, BOOL *stop) {
        (void)enclosingRange;
        (void)stop;

        if (line.length == 0) return;

        if ([line hasPrefix:@"%%"]) {
            [storage addAttribute:NSForegroundColorAttributeName
                            value:[NSColor colorWithRed:0.48 green:0.66 blue:0.52 alpha:1.0]
                            range:lineRange];
            return;
        }

        NSArray<NSString *> *arrows = @[ @"<==>", @"<-.->", @"<-->", @"==>", @"-.->", @"-->", @"---", @"<:::", @":::" ];
        NSCharacterSet *wordSet = [NSCharacterSet characterSetWithCharactersInString:@"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_"];

        NSUInteger idx = 0;
        while (idx < line.length) {
            NSString *remaining = [line substringFromIndex:idx];
            BOOL matchedArrow = NO;
            for (NSString *arrow in arrows) {
                if ([remaining hasPrefix:arrow]) {
                    [storage addAttribute:NSForegroundColorAttributeName
                                    value:[NSColor colorWithRed:0.96 green:0.43 blue:0.43 alpha:1.0]
                                    range:NSMakeRange(lineRange.location + idx, arrow.length)];
                    idx += arrow.length;
                    matchedArrow = YES;
                    break;
                }
            }
            if (matchedArrow) continue;

            unichar c = [line characterAtIndex:idx];
            if (c == '"') {
                NSUInteger start = idx;
                idx += 1;
                while (idx < line.length) {
                    unichar q = [line characterAtIndex:idx];
                    idx += 1;
                    if (q == '"') break;
                }
                [storage addAttribute:NSForegroundColorAttributeName
                                value:[NSColor colorWithRed:0.62 green:0.83 blue:0.57 alpha:1.0]
                                range:NSMakeRange(lineRange.location + start, idx - start)];
                continue;
            }

            if ([wordSet characterIsMember:c]) {
                NSUInteger start = idx;
                while (idx < line.length && [wordSet characterIsMember:[line characterAtIndex:idx]]) {
                    idx += 1;
                }
                NSString *word = [line substringWithRange:NSMakeRange(start, idx - start)];
                NSColor *color = [self editorColorForWord:word];
                [storage addAttribute:NSForegroundColorAttributeName
                                value:color
                                range:NSMakeRange(lineRange.location + start, idx - start)];
                continue;
            }

            idx += 1;
        }
    }];

    [storage endEditing];
    self.isApplyingHighlighting = NO;
    self.editorTextView.typingAttributes = baseAttrs;
}

- (void)debounceSyntaxHighlighting {
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(applySyntaxHighlightingIfCurrent) object:nil];
    [self performSelector:@selector(applySyntaxHighlightingIfCurrent) withObject:nil afterDelay:0.06];
}

- (void)applySyntaxHighlightingIfCurrent {
    if (self.isApplyingHighlighting) return;
    [self applySyntaxHighlighting];
}

- (void)requestEditorAnalysis {
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(processEditorChange) object:nil];
    [self performSelector:@selector(processEditorChange) withObject:nil afterDelay:0.45];
}

- (void)clearCommandContext {
    self.currentCommandContextId = nil;
    self.currentCommandContextDisplay = nil;
    self.contextLabel.stringValue = @"it=-";
}

- (void)updateCommandContextId:(NSString *)contextId display:(NSString *)displayText {
    NSString *trimmedId = [contextId stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] ?: @"";
    NSString *trimmedDisplay = [displayText stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] ?: @"";
    if (trimmedId.length == 0) {
        [self clearCommandContext];
        return;
    }

    self.currentCommandContextId = [trimmedId copy];
    self.currentCommandContextDisplay = trimmedDisplay.length > 0 ? [trimmedDisplay copy] : [trimmedId copy];
    self.contextLabel.stringValue = [NSString stringWithFormat:@"it=%@", self.currentCommandContextDisplay ?: self.currentCommandContextId];
}

- (void)replaceEditorSourceFromCommand:(NSString *)source status:(NSString *)statusMessage contextId:(NSString *)contextId contextDisplay:(NSString *)contextDisplay {
    if (!self.editorTextView) return;

    self.isSynchronizingEditor = YES;
    NSRange previousSelection = self.editorTextView.selectedRange;
    [self.editorTextView setString:source ?: @""];
    [self applySyntaxHighlighting];
    self.editorGeneration += 1;
    [self markDocumentEdited:YES];
    [self requestEditorAnalysis];

    NSUInteger maxLocation = self.editorTextView.string.length;
    NSUInteger clampedLocation = MIN(previousSelection.location, maxLocation);
    NSUInteger clampedLength = MIN(previousSelection.length, maxLocation - clampedLocation);
    [self.editorTextView setSelectedRange:NSMakeRange(clampedLocation, clampedLength)];
    [self.editorTextView scrollRangeToVisible:NSMakeRange(clampedLocation, clampedLength)];
    self.isSynchronizingEditor = NO;

    [self updateCommandContextId:contextId display:contextDisplay];
    self.statusLabel.stringValue = statusMessage ?: @"Command applied.";
}

- (NSTextField *)freeformPanelLabel:(NSString *)text size:(CGFloat)size weight:(NSFontWeight)weight color:(NSColor *)color {
    NSTextField *label = [NSTextField labelWithString:text ?: @""];
    label.translatesAutoresizingMaskIntoConstraints = NO;
    label.font = [NSFont systemFontOfSize:size weight:weight];
    label.textColor = color;
    label.lineBreakMode = NSLineBreakByWordWrapping;
    label.maximumNumberOfLines = 0;
    return label;
}

- (NSView *)freeformSectionViewWithTitle:(NSString *)title lines:(NSArray<NSString *> *)lines {
    NSStackView *section = [[NSStackView alloc] initWithFrame:NSZeroRect];
    section.translatesAutoresizingMaskIntoConstraints = NO;
    section.orientation = NSUserInterfaceLayoutOrientationVertical;
    section.alignment = NSLayoutAttributeLeading;
    section.spacing = 6.0;

    [section addArrangedSubview:[self freeformPanelLabel:title
                                                    size:11.0
                                                  weight:NSFontWeightSemibold
                                                   color:[NSColor colorWithRed:0.55 green:0.60 blue:0.68 alpha:1.0]]];

    for (NSString *line in lines) {
        [section addArrangedSubview:[self freeformPanelLabel:line
                                                        size:12.0
                                                      weight:NSFontWeightRegular
                                                       color:[NSColor colorWithRed:0.87 green:0.89 blue:0.93 alpha:1.0]]];
    }

    return section;
}

- (NSString *)selectedObjectIdForPopup:(NSPopUpButton *)popup {
    id representedObject = popup.selectedItem.representedObject;
    return [representedObject isKindOfClass:[NSString class]] ? representedObject : nil;
}

- (void)populateFreeformConnectorPopup:(NSPopUpButton *)popup
                           withObjects:(NSArray<NSDictionary *> *)objects
                       preferredObject:(NSString *)preferredObjectId {
    [popup removeAllItems];
    for (NSDictionary *object in objects) {
        NSString *title = [object[@"title"] isKindOfClass:[NSString class]] ? object[@"title"] : @"Untitled";
        NSString *objectId = [object[@"id"] isKindOfClass:[NSString class]] ? object[@"id"] : nil;
        if (objectId.length == 0) continue;
        NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:title action:nil keyEquivalent:@""];
        item.representedObject = objectId;
        [popup.menu addItem:item];
    }

    if (popup.numberOfItems == 0) {
        [popup addItemWithTitle:@"Need at least two shapes or groups"];
        popup.enabled = NO;
        return;
    }

    popup.enabled = YES;
    if (preferredObjectId.length > 0) {
        for (NSMenuItem *item in popup.itemArray) {
            if ([item.representedObject isKindOfClass:[NSString class]] && [item.representedObject isEqualToString:preferredObjectId]) {
                [popup selectItem:item];
                return;
            }
        }
    }
    [popup selectItemAtIndex:0];
}

- (void)syncFreeformConnectorControls {
    NSArray<NSDictionary *> *objects = [self.freeformCanvasComponent connectableObjects];
    NSString *selectedObjectId = self.freeformCanvasComponent.selectedConnectableObjectId;
    NSString *currentSourceId = [self selectedObjectIdForPopup:self.freeformConnectorSourcePopup];
    NSString *currentTargetId = [self selectedObjectIdForPopup:self.freeformConnectorTargetPopup];

    [self populateFreeformConnectorPopup:self.freeformConnectorSourcePopup
                             withObjects:objects
                         preferredObject:selectedObjectId ?: currentSourceId];

    NSString *sourceId = [self selectedObjectIdForPopup:self.freeformConnectorSourcePopup];
    [self populateFreeformConnectorPopup:self.freeformConnectorTargetPopup
                             withObjects:objects
                         preferredObject:currentTargetId];

    NSString *targetId = [self selectedObjectIdForPopup:self.freeformConnectorTargetPopup];
    if (sourceId.length > 0 && [sourceId isEqualToString:targetId]) {
        for (NSMenuItem *item in self.freeformConnectorTargetPopup.itemArray) {
            if ([item.representedObject isKindOfClass:[NSString class]] && ![item.representedObject isEqualToString:sourceId]) {
                [self.freeformConnectorTargetPopup selectItem:item];
                break;
            }
        }
    }

    sourceId = [self selectedObjectIdForPopup:self.freeformConnectorSourcePopup];
    targetId = [self selectedObjectIdForPopup:self.freeformConnectorTargetPopup];
    const BOOL hasEnoughObjects = objects.count >= 2;
    self.freeformConnectorSourcePopup.enabled = hasEnoughObjects;
    self.freeformConnectorTargetPopup.enabled = hasEnoughObjects;
    self.freeformAddConnectorButton.enabled = hasEnoughObjects && sourceId.length > 0 && targetId.length > 0 && ![sourceId isEqualToString:targetId];
}

- (IBAction)freeformConnectorPopupSelectionChanged:(id)sender {
    (void)sender;
    [self syncFreeformConnectorControls];
}

- (BOOL)isSequenceFreeformGraph {
    return self.freeformCanvasComponent.graphType == MerrowFreeformGraphTypeSequence;
}

- (NSScrollView *)activeFreeformInspectorScrollView {
    return [self isSequenceFreeformGraph] ? self.sequenceToolsScrollView : self.freeformToolsScrollView;
}

- (NSScrollView *)createFreeformToolsScrollView {
    NSStackView *stack = [[NSStackView alloc] initWithFrame:NSZeroRect];
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    stack.orientation = NSUserInterfaceLayoutOrientationVertical;
    stack.alignment = NSLayoutAttributeLeading;
    stack.spacing = 16.0;
    stack.edgeInsets = NSEdgeInsetsMake(16.0, 16.0, 24.0, 16.0);

        [stack addArrangedSubview:[self freeformSectionViewWithTitle:@"CANVAS"
                                                                                                                     lines:@[
                                                                                                                             @"Set the freeform background color and transparency used by the canvas and image exports.",
                                                                                                                     ]]];

        NSStackView *backgroundRow = [[NSStackView alloc] initWithFrame:NSZeroRect];
        backgroundRow.translatesAutoresizingMaskIntoConstraints = NO;
        backgroundRow.orientation = NSUserInterfaceLayoutOrientationHorizontal;
        backgroundRow.alignment = NSLayoutAttributeCenterY;
        backgroundRow.spacing = 10.0;
        [backgroundRow addArrangedSubview:[self freeformPanelLabel:@"Background"
                                                                                                                    size:11.0
                                                                                                                weight:NSFontWeightSemibold
                                                                                                                 color:[NSColor colorWithRed:0.55 green:0.60 blue:0.68 alpha:1.0]]];
        self.freeformCanvasBackgroundColorWell = [[NSColorWell alloc] initWithFrame:NSMakeRect(0.0, 0.0, 44.0, 28.0)];
        self.freeformCanvasBackgroundColorWell.translatesAutoresizingMaskIntoConstraints = NO;
        self.freeformCanvasBackgroundColorWell.target = self;
        self.freeformCanvasBackgroundColorWell.action = @selector(applyFreeformCanvasBackgroundColor:);
        [backgroundRow addArrangedSubview:self.freeformCanvasBackgroundColorWell];
        [stack addArrangedSubview:backgroundRow];

        [stack addArrangedSubview:[self freeformPanelLabel:@"Transparency"
                                                                                                    size:11.0
                                                                                                weight:NSFontWeightSemibold
                                                                                                 color:[NSColor colorWithRed:0.55 green:0.60 blue:0.68 alpha:1.0]]];
        self.freeformCanvasBackgroundOpacitySlider = [NSSlider sliderWithValue:1.0 minValue:0.0 maxValue:1.0 target:self action:@selector(applyFreeformCanvasBackgroundOpacity:)];
        self.freeformCanvasBackgroundOpacitySlider.translatesAutoresizingMaskIntoConstraints = NO;
        self.freeformCanvasBackgroundOpacitySlider.continuous = YES;
        [stack addArrangedSubview:self.freeformCanvasBackgroundOpacitySlider];
        self.freeformCanvasBackgroundOpacityValueLabel = [self freeformPanelLabel:@"100%"
                                                                                                                                                 size:11.0
                                                                                                                                             weight:NSFontWeightRegular
                                                                                                                                                color:[NSColor colorWithRed:0.79 green:0.82 blue:0.88 alpha:1.0]];
        [stack addArrangedSubview:self.freeformCanvasBackgroundOpacityValueLabel];

    [stack addArrangedSubview:[self freeformSectionViewWithTitle:@"CREATE"
                                                           lines:@[
                                                               @"Choose a shape, then click Add Shape or Add Group. The next click on the canvas places it.",
                                                               @"If a group is selected, new objects are nested inside that group.",
                                                           ]]];

    [stack addArrangedSubview:[self freeformPanelLabel:@"Shape"
                                                  size:11.0
                                                weight:NSFontWeightSemibold
                                                 color:[NSColor colorWithRed:0.55 green:0.60 blue:0.68 alpha:1.0]]];
    self.freeformShapePopup = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(0.0, 0.0, 220.0, 26.0) pullsDown:NO];
    self.freeformShapePopup.translatesAutoresizingMaskIntoConstraints = NO;
    NSArray<NSDictionary *> *shapeOptions = @[
        @{ @"title": @"Rounded Rectangle", @"shape": @1 },
        @{ @"title": @"Rectangle", @"shape": @0 },
        @{ @"title": @"Diamond", @"shape": @2 },
        @{ @"title": @"Circle", @"shape": @3 },
        @{ @"title": @"Hexagon", @"shape": @4 },
        @{ @"title": @"Cylinder", @"shape": @5 },
        @{ @"title": @"Stadium", @"shape": @6 },
        @{ @"title": @"Subroutine", @"shape": @11 },
    ];
    for (NSDictionary *option in shapeOptions) {
        NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:option[@"title"] action:nil keyEquivalent:@""];
        item.representedObject = option[@"shape"];
        [self.freeformShapePopup.menu addItem:item];
    }
    [self.freeformShapePopup selectItemAtIndex:0];
    [stack addArrangedSubview:self.freeformShapePopup];

    NSStackView *createButtonsRow = [[NSStackView alloc] initWithFrame:NSZeroRect];
    createButtonsRow.translatesAutoresizingMaskIntoConstraints = NO;
    createButtonsRow.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    createButtonsRow.alignment = NSLayoutAttributeCenterY;
    createButtonsRow.spacing = 8.0;

    self.freeformAddShapeButton = [NSButton buttonWithTitle:@"Add Shape" target:self action:@selector(beginFreeformAddShape:)];
    self.freeformAddShapeButton.translatesAutoresizingMaskIntoConstraints = NO;
    [createButtonsRow addArrangedSubview:self.freeformAddShapeButton];

    self.freeformAddGroupButton = [NSButton buttonWithTitle:@"Add Group" target:self action:@selector(beginFreeformAddGroup:)];
    self.freeformAddGroupButton.translatesAutoresizingMaskIntoConstraints = NO;
    [createButtonsRow addArrangedSubview:self.freeformAddGroupButton];

    self.freeformCancelCreateButton = [NSButton buttonWithTitle:@"Cancel" target:self action:@selector(cancelFreeformInsertion:)];
    self.freeformCancelCreateButton.translatesAutoresizingMaskIntoConstraints = NO;
    self.freeformCancelCreateButton.enabled = NO;
    [createButtonsRow addArrangedSubview:self.freeformCancelCreateButton];

    [stack addArrangedSubview:createButtonsRow];

    self.freeformCreateStatusLabel = [self freeformPanelLabel:@"Choose Add Shape or Add Group, then click the canvas to place it."
                                                         size:12.0
                                                       weight:NSFontWeightRegular
                                                        color:[NSColor colorWithRed:0.87 green:0.89 blue:0.93 alpha:1.0]];
    [stack addArrangedSubview:self.freeformCreateStatusLabel];

    self.freeformSelectionLabel = [self freeformPanelLabel:@"No selection"
                                                      size:12.0
                                                    weight:NSFontWeightSemibold
                                                     color:[NSColor colorWithRed:0.96 green:0.97 blue:0.99 alpha:1.0]];
    [stack addArrangedSubview:[self freeformSectionViewWithTitle:@"SELECTION"
                                                           lines:@[
                                                               @"Click a node to select it. Shift-click a group to select and drag the whole subgraph.",
                                                           ]]];
    [stack addArrangedSubview:self.freeformSelectionLabel];

    NSTextField *labelCaption = [self freeformPanelLabel:@"Node label"
                                                    size:11.0
                                                  weight:NSFontWeightSemibold
                                                   color:[NSColor colorWithRed:0.55 green:0.60 blue:0.68 alpha:1.0]];
    [stack addArrangedSubview:labelCaption];

    self.freeformNodeLabelField = [[NSTextField alloc] initWithFrame:NSZeroRect];
    self.freeformNodeLabelField.translatesAutoresizingMaskIntoConstraints = NO;
    self.freeformNodeLabelField.font = [NSFont systemFontOfSize:12.0 weight:NSFontWeightRegular];
    self.freeformNodeLabelField.placeholderString = @"Select a node or group to edit its label";
    self.freeformNodeLabelField.target = self;
    self.freeformNodeLabelField.action = @selector(applyFreeformNodeLabel:);
    self.freeformNodeLabelField.enabled = NO;
    [stack addArrangedSubview:self.freeformNodeLabelField];
    [self.freeformNodeLabelField.widthAnchor constraintGreaterThanOrEqualToConstant:240.0].active = YES;

        NSStackView *sizeRow = [[NSStackView alloc] initWithFrame:NSZeroRect];
        sizeRow.translatesAutoresizingMaskIntoConstraints = NO;
        sizeRow.orientation = NSUserInterfaceLayoutOrientationHorizontal;
        sizeRow.alignment = NSLayoutAttributeCenterY;
        sizeRow.spacing = 8.0;

        [sizeRow addArrangedSubview:[self freeformPanelLabel:@"W"
                                                                                                        size:11.0
                                                                                                    weight:NSFontWeightSemibold
                                                                                                     color:[NSColor colorWithRed:0.55 green:0.60 blue:0.68 alpha:1.0]]];
        self.freeformWidthField = [[NSTextField alloc] initWithFrame:NSMakeRect(0.0, 0.0, 72.0, 24.0)];
        self.freeformWidthField.translatesAutoresizingMaskIntoConstraints = NO;
        self.freeformWidthField.font = [NSFont systemFontOfSize:12.0 weight:NSFontWeightRegular];
        self.freeformWidthField.placeholderString = @"Width";
        self.freeformWidthField.target = self;
        self.freeformWidthField.action = @selector(applyFreeformObjectWidth:);
        self.freeformWidthField.enabled = NO;
        [self.freeformWidthField.widthAnchor constraintEqualToConstant:78.0].active = YES;
        [sizeRow addArrangedSubview:self.freeformWidthField];

        [sizeRow addArrangedSubview:[self freeformPanelLabel:@"H"
                                                                                                        size:11.0
                                                                                                    weight:NSFontWeightSemibold
                                                                                                     color:[NSColor colorWithRed:0.55 green:0.60 blue:0.68 alpha:1.0]]];
        self.freeformHeightField = [[NSTextField alloc] initWithFrame:NSMakeRect(0.0, 0.0, 72.0, 24.0)];
        self.freeformHeightField.translatesAutoresizingMaskIntoConstraints = NO;
        self.freeformHeightField.font = [NSFont systemFontOfSize:12.0 weight:NSFontWeightRegular];
        self.freeformHeightField.placeholderString = @"Height";
        self.freeformHeightField.target = self;
        self.freeformHeightField.action = @selector(applyFreeformObjectHeight:);
        self.freeformHeightField.enabled = NO;
        [self.freeformHeightField.widthAnchor constraintEqualToConstant:78.0].active = YES;
        [sizeRow addArrangedSubview:self.freeformHeightField];

        [stack addArrangedSubview:[self freeformPanelLabel:@"Size"
                                                                                                    size:11.0
                                                                                                weight:NSFontWeightSemibold
                                                                                                 color:[NSColor colorWithRed:0.55 green:0.60 blue:0.68 alpha:1.0]]];
        [stack addArrangedSubview:sizeRow];

        NSStackView *fillRow = [[NSStackView alloc] initWithFrame:NSZeroRect];
        fillRow.translatesAutoresizingMaskIntoConstraints = NO;
        fillRow.orientation = NSUserInterfaceLayoutOrientationHorizontal;
        fillRow.alignment = NSLayoutAttributeCenterY;
        fillRow.spacing = 10.0;
        [fillRow addArrangedSubview:[self freeformPanelLabel:@"Fill"
                                                                                                        size:11.0
                                                                                                    weight:NSFontWeightSemibold
                                                                                                     color:[NSColor colorWithRed:0.55 green:0.60 blue:0.68 alpha:1.0]]];
        self.freeformFillColorWell = [[NSColorWell alloc] initWithFrame:NSMakeRect(0.0, 0.0, 44.0, 28.0)];
        self.freeformFillColorWell.translatesAutoresizingMaskIntoConstraints = NO;
        self.freeformFillColorWell.target = self;
        self.freeformFillColorWell.action = @selector(applyFreeformFillColor:);
        self.freeformFillColorWell.enabled = NO;
        [fillRow addArrangedSubview:self.freeformFillColorWell];
        [stack addArrangedSubview:fillRow];

        NSStackView *strokeRow = [[NSStackView alloc] initWithFrame:NSZeroRect];
        strokeRow.translatesAutoresizingMaskIntoConstraints = NO;
        strokeRow.orientation = NSUserInterfaceLayoutOrientationHorizontal;
        strokeRow.alignment = NSLayoutAttributeCenterY;
        strokeRow.spacing = 10.0;
        [strokeRow addArrangedSubview:[self freeformPanelLabel:@"Stroke"
                                                                                                            size:11.0
                                                                                                        weight:NSFontWeightSemibold
                                                                                                         color:[NSColor colorWithRed:0.55 green:0.60 blue:0.68 alpha:1.0]]];
        self.freeformStrokeColorWell = [[NSColorWell alloc] initWithFrame:NSMakeRect(0.0, 0.0, 44.0, 28.0)];
        self.freeformStrokeColorWell.translatesAutoresizingMaskIntoConstraints = NO;
        self.freeformStrokeColorWell.target = self;
        self.freeformStrokeColorWell.action = @selector(applyFreeformStrokeColor:);
        self.freeformStrokeColorWell.enabled = NO;
        [strokeRow addArrangedSubview:self.freeformStrokeColorWell];
        [stack addArrangedSubview:strokeRow];

        [stack addArrangedSubview:[self freeformPanelLabel:@"Border thickness"
                                                                                                    size:11.0
                                                                                                weight:NSFontWeightSemibold
                                                                                                 color:[NSColor colorWithRed:0.55 green:0.60 blue:0.68 alpha:1.0]]];
        self.freeformStrokeWidthSlider = [NSSlider sliderWithValue:2.0 minValue:1.0 maxValue:12.0 target:self action:@selector(applyFreeformStrokeWidth:)];
        self.freeformStrokeWidthSlider.translatesAutoresizingMaskIntoConstraints = NO;
        self.freeformStrokeWidthSlider.continuous = YES;
        self.freeformStrokeWidthSlider.enabled = NO;
        [stack addArrangedSubview:self.freeformStrokeWidthSlider];
        self.freeformStrokeWidthValueLabel = [self freeformPanelLabel:@"2.0 pt"
                                                                                                                         size:11.0
                                                                                                                     weight:NSFontWeightRegular
                                                                                                                        color:[NSColor colorWithRed:0.79 green:0.82 blue:0.88 alpha:1.0]];
        [stack addArrangedSubview:self.freeformStrokeWidthValueLabel];

        [stack addArrangedSubview:[self freeformSectionViewWithTitle:@"CONNECTOR STYLE"
                                                                                                                     lines:@[
                                                                    @"Use Start Connector from the canvas context menu, or pick a source and target below to add one from the inspector.",
                                                                    @"Select a connector to edit its label, stroke, pattern, thickness, and arrow direction, or drag either endpoint handle to reconnect it.",
                                                                                                                     ]]];

        [stack addArrangedSubview:[self freeformPanelLabel:@"Add connector"
                                                                                                    size:11.0
                                                                                                weight:NSFontWeightSemibold
                                                                                                 color:[NSColor colorWithRed:0.55 green:0.60 blue:0.68 alpha:1.0]]];
        self.freeformConnectorSourcePopup = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(0.0, 0.0, 220.0, 26.0) pullsDown:NO];
        self.freeformConnectorSourcePopup.translatesAutoresizingMaskIntoConstraints = NO;
        self.freeformConnectorSourcePopup.target = self;
        self.freeformConnectorSourcePopup.action = @selector(freeformConnectorPopupSelectionChanged:);
        [stack addArrangedSubview:[self freeformPanelLabel:@"From"
                                                                                                    size:11.0
                                                                                                weight:NSFontWeightSemibold
                                                                                                 color:[NSColor colorWithRed:0.55 green:0.60 blue:0.68 alpha:1.0]]];
        [stack addArrangedSubview:self.freeformConnectorSourcePopup];

        self.freeformConnectorTargetPopup = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(0.0, 0.0, 220.0, 26.0) pullsDown:NO];
        self.freeformConnectorTargetPopup.translatesAutoresizingMaskIntoConstraints = NO;
        self.freeformConnectorTargetPopup.target = self;
        self.freeformConnectorTargetPopup.action = @selector(freeformConnectorPopupSelectionChanged:);
        [stack addArrangedSubview:[self freeformPanelLabel:@"To"
                                                                                                    size:11.0
                                                                                                weight:NSFontWeightSemibold
                                                                                                 color:[NSColor colorWithRed:0.55 green:0.60 blue:0.68 alpha:1.0]]];
        [stack addArrangedSubview:self.freeformConnectorTargetPopup];

        self.freeformAddConnectorButton = [NSButton buttonWithTitle:@"Add Connector" target:self action:@selector(addFreeformConnector:)];
        self.freeformAddConnectorButton.translatesAutoresizingMaskIntoConstraints = NO;
        self.freeformAddConnectorButton.enabled = NO;
        [stack addArrangedSubview:self.freeformAddConnectorButton];

        self.freeformEdgeLabelField = [[NSTextField alloc] initWithFrame:NSZeroRect];
        self.freeformEdgeLabelField.translatesAutoresizingMaskIntoConstraints = NO;
        self.freeformEdgeLabelField.font = [NSFont systemFontOfSize:12.0 weight:NSFontWeightRegular];
        self.freeformEdgeLabelField.placeholderString = @"Select a connector to edit its label";
        self.freeformEdgeLabelField.target = self;
        self.freeformEdgeLabelField.action = @selector(applyFreeformEdgeLabel:);
        self.freeformEdgeLabelField.enabled = NO;
        [stack addArrangedSubview:[self freeformPanelLabel:@"Connector label"
                                                                                                    size:11.0
                                                                                                weight:NSFontWeightSemibold
                                                                                                 color:[NSColor colorWithRed:0.55 green:0.60 blue:0.68 alpha:1.0]]];
        [stack addArrangedSubview:self.freeformEdgeLabelField];
        [self.freeformEdgeLabelField.widthAnchor constraintGreaterThanOrEqualToConstant:240.0].active = YES;

        NSStackView *edgeColorRow = [[NSStackView alloc] initWithFrame:NSZeroRect];
        edgeColorRow.translatesAutoresizingMaskIntoConstraints = NO;
        edgeColorRow.orientation = NSUserInterfaceLayoutOrientationHorizontal;
        edgeColorRow.alignment = NSLayoutAttributeCenterY;
        edgeColorRow.spacing = 10.0;
        [edgeColorRow addArrangedSubview:[self freeformPanelLabel:@"Connector color"
                                                                                                                 size:11.0
                                                                                                             weight:NSFontWeightSemibold
                                                                                                                color:[NSColor colorWithRed:0.55 green:0.60 blue:0.68 alpha:1.0]]];
        self.freeformEdgeColorWell = [[NSColorWell alloc] initWithFrame:NSMakeRect(0.0, 0.0, 44.0, 28.0)];
        self.freeformEdgeColorWell.translatesAutoresizingMaskIntoConstraints = NO;
        self.freeformEdgeColorWell.target = self;
        self.freeformEdgeColorWell.action = @selector(applyFreeformEdgeColor:);
        self.freeformEdgeColorWell.enabled = NO;
        [edgeColorRow addArrangedSubview:self.freeformEdgeColorWell];
        [stack addArrangedSubview:edgeColorRow];

        [stack addArrangedSubview:[self freeformPanelLabel:@"Connector thickness"
                                                                                                    size:11.0
                                                                                                weight:NSFontWeightSemibold
                                                                                                 color:[NSColor colorWithRed:0.55 green:0.60 blue:0.68 alpha:1.0]]];
        self.freeformEdgeThicknessSlider = [NSSlider sliderWithValue:2.0 minValue:1.0 maxValue:12.0 target:self action:@selector(applyFreeformEdgeThickness:)];
        self.freeformEdgeThicknessSlider.translatesAutoresizingMaskIntoConstraints = NO;
        self.freeformEdgeThicknessSlider.continuous = YES;
        self.freeformEdgeThicknessSlider.enabled = NO;
        [stack addArrangedSubview:self.freeformEdgeThicknessSlider];
        self.freeformEdgeThicknessValueLabel = [self freeformPanelLabel:@"2.0 pt"
                                                                                                                             size:11.0
                                                                                                                         weight:NSFontWeightRegular
                                                                                                                            color:[NSColor colorWithRed:0.79 green:0.82 blue:0.88 alpha:1.0]];
        [stack addArrangedSubview:self.freeformEdgeThicknessValueLabel];

        [stack addArrangedSubview:[self freeformPanelLabel:@"Connector pattern"
                                                                                                    size:11.0
                                                                                                weight:NSFontWeightSemibold
                                                                                                 color:[NSColor colorWithRed:0.55 green:0.60 blue:0.68 alpha:1.0]]];
        self.freeformEdgePatternPopup = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(0.0, 0.0, 220.0, 26.0) pullsDown:NO];
        self.freeformEdgePatternPopup.translatesAutoresizingMaskIntoConstraints = NO;
        [self.freeformEdgePatternPopup addItemsWithTitles:@[@"Solid", @"Dashed", @"Dotted", @"Thick"]];
        self.freeformEdgePatternPopup.target = self;
        self.freeformEdgePatternPopup.action = @selector(applyFreeformEdgePattern:);
        self.freeformEdgePatternPopup.enabled = NO;
        [stack addArrangedSubview:self.freeformEdgePatternPopup];

        [stack addArrangedSubview:[self freeformPanelLabel:@"Arrow direction"
                                                                                                    size:11.0
                                                                                                weight:NSFontWeightSemibold
                                                                                                 color:[NSColor colorWithRed:0.55 green:0.60 blue:0.68 alpha:1.0]]];
        self.freeformEdgeArrowPopup = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(0.0, 0.0, 220.0, 26.0) pullsDown:NO];
        self.freeformEdgeArrowPopup.translatesAutoresizingMaskIntoConstraints = NO;
        [self.freeformEdgeArrowPopup addItemsWithTitles:@[@"None", @"Forward", @"Reverse", @"Both"]];
        self.freeformEdgeArrowPopup.target = self;
        self.freeformEdgeArrowPopup.action = @selector(applyFreeformEdgeArrowMode:);
        self.freeformEdgeArrowPopup.enabled = NO;
        [stack addArrangedSubview:self.freeformEdgeArrowPopup];

    NSView *document = [[NSView alloc] initWithFrame:NSZeroRect];
    document.translatesAutoresizingMaskIntoConstraints = NO;
    [document addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[
        [stack.leadingAnchor constraintEqualToAnchor:document.leadingAnchor],
        [stack.trailingAnchor constraintEqualToAnchor:document.trailingAnchor],
        [stack.topAnchor constraintEqualToAnchor:document.topAnchor],
        [stack.bottomAnchor constraintEqualToAnchor:document.bottomAnchor],
        [stack.widthAnchor constraintEqualToAnchor:document.widthAnchor],
    ]];

    NSScrollView *scrollView = [[NSScrollView alloc] initWithFrame:NSZeroRect];
    scrollView.translatesAutoresizingMaskIntoConstraints = NO;
    scrollView.hasVerticalScroller = YES;
    scrollView.hasHorizontalScroller = NO;
    scrollView.autohidesScrollers = YES;
    scrollView.borderType = NSNoBorder;
    scrollView.backgroundColor = [NSColor colorWithRed:0.10 green:0.11 blue:0.13 alpha:1.0];
    scrollView.drawsBackground = YES;
    scrollView.documentView = document;
    return scrollView;
}

- (NSScrollView *)createSequenceToolsScrollView {
        NSStackView *stack = [[NSStackView alloc] initWithFrame:NSZeroRect];
        stack.translatesAutoresizingMaskIntoConstraints = NO;
        stack.orientation = NSUserInterfaceLayoutOrientationVertical;
        stack.alignment = NSLayoutAttributeLeading;
        stack.spacing = 16.0;
        stack.edgeInsets = NSEdgeInsetsMake(16.0, 16.0, 24.0, 16.0);

        [stack addArrangedSubview:[self freeformSectionViewWithTitle:@"SEQUENCE"
                                                                                                                     lines:@[
                                                                                                                             @"Sequence diagrams load into the freeform canvas as participants, messages, notes, activations, and fragments.",
                                                                                                                             @"Use the canvas to reposition elements, then edit their labels and styling here with sequence-focused controls.",
                                                                                                                     ]]];

        [stack addArrangedSubview:[self freeformSectionViewWithTitle:@"CANVAS"
                                                                                                                     lines:@[
                                                                                                                             @"Set the sequence canvas background used by the freeform workspace and image exports.",
                                                                                                                     ]]];

        NSStackView *backgroundRow = [[NSStackView alloc] initWithFrame:NSZeroRect];
        backgroundRow.translatesAutoresizingMaskIntoConstraints = NO;
        backgroundRow.orientation = NSUserInterfaceLayoutOrientationHorizontal;
        backgroundRow.alignment = NSLayoutAttributeCenterY;
        backgroundRow.spacing = 10.0;
        [backgroundRow addArrangedSubview:[self freeformPanelLabel:@"Background"
                                                                                                                    size:11.0
                                                                                                                weight:NSFontWeightSemibold
                                                                                                                 color:[NSColor colorWithRed:0.55 green:0.60 blue:0.68 alpha:1.0]]];
        self.sequenceCanvasBackgroundColorWell = [[NSColorWell alloc] initWithFrame:NSMakeRect(0.0, 0.0, 44.0, 28.0)];
        self.sequenceCanvasBackgroundColorWell.translatesAutoresizingMaskIntoConstraints = NO;
        self.sequenceCanvasBackgroundColorWell.target = self;
        self.sequenceCanvasBackgroundColorWell.action = @selector(applyFreeformCanvasBackgroundColor:);
        [backgroundRow addArrangedSubview:self.sequenceCanvasBackgroundColorWell];
        [stack addArrangedSubview:backgroundRow];

        [stack addArrangedSubview:[self freeformPanelLabel:@"Transparency"
                                                                                                    size:11.0
                                                                                                weight:NSFontWeightSemibold
                                                                                                 color:[NSColor colorWithRed:0.55 green:0.60 blue:0.68 alpha:1.0]]];
        self.sequenceCanvasBackgroundOpacitySlider = [NSSlider sliderWithValue:1.0 minValue:0.0 maxValue:1.0 target:self action:@selector(applyFreeformCanvasBackgroundOpacity:)];
        self.sequenceCanvasBackgroundOpacitySlider.translatesAutoresizingMaskIntoConstraints = NO;
        self.sequenceCanvasBackgroundOpacitySlider.continuous = YES;
        [stack addArrangedSubview:self.sequenceCanvasBackgroundOpacitySlider];
        self.sequenceCanvasBackgroundOpacityValueLabel = [self freeformPanelLabel:@"100%"
                                                                                                                                                 size:11.0
                                                                                                                                             weight:NSFontWeightRegular
                                                                                                                                                color:[NSColor colorWithRed:0.79 green:0.82 blue:0.88 alpha:1.0]];
        [stack addArrangedSubview:self.sequenceCanvasBackgroundOpacityValueLabel];

        [stack addArrangedSubview:[self freeformSectionViewWithTitle:@"SELECTION"
                                                                                                                     lines:@[
                                                                                                                             @"Participants, notes, activations, and fragments map to editable objects in the canvas.",
                                                                                                                             @"Select a message to edit its label and line style, or select a sequence element to adjust its size and colors.",
                                                                                                                     ]]];
        self.sequenceSelectionLabel = [self freeformPanelLabel:@"No selection"
                                                                                                            size:12.0
                                                                                                        weight:NSFontWeightSemibold
                                                                                                         color:[NSColor colorWithRed:0.96 green:0.97 blue:0.99 alpha:1.0]];
        [stack addArrangedSubview:self.sequenceSelectionLabel];

        [stack addArrangedSubview:[self freeformPanelLabel:@"Element label"
                                                                                                    size:11.0
                                                                                                weight:NSFontWeightSemibold
                                                                                                 color:[NSColor colorWithRed:0.55 green:0.60 blue:0.68 alpha:1.0]]];
        self.sequenceElementLabelField = [[NSTextField alloc] initWithFrame:NSZeroRect];
        self.sequenceElementLabelField.translatesAutoresizingMaskIntoConstraints = NO;
        self.sequenceElementLabelField.font = [NSFont systemFontOfSize:12.0 weight:NSFontWeightRegular];
        self.sequenceElementLabelField.placeholderString = @"Select a participant, note, or fragment to edit its label";
        self.sequenceElementLabelField.target = self;
        self.sequenceElementLabelField.action = @selector(applyFreeformNodeLabel:);
        self.sequenceElementLabelField.enabled = NO;
        [stack addArrangedSubview:self.sequenceElementLabelField];
        [self.sequenceElementLabelField.widthAnchor constraintGreaterThanOrEqualToConstant:240.0].active = YES;

        NSStackView *sizeRow = [[NSStackView alloc] initWithFrame:NSZeroRect];
        sizeRow.translatesAutoresizingMaskIntoConstraints = NO;
        sizeRow.orientation = NSUserInterfaceLayoutOrientationHorizontal;
        sizeRow.alignment = NSLayoutAttributeCenterY;
        sizeRow.spacing = 8.0;
        [sizeRow addArrangedSubview:[self freeformPanelLabel:@"W"
                                                                                                        size:11.0
                                                                                                    weight:NSFontWeightSemibold
                                                                                                     color:[NSColor colorWithRed:0.55 green:0.60 blue:0.68 alpha:1.0]]];
        self.sequenceWidthField = [[NSTextField alloc] initWithFrame:NSMakeRect(0.0, 0.0, 72.0, 24.0)];
        self.sequenceWidthField.translatesAutoresizingMaskIntoConstraints = NO;
        self.sequenceWidthField.font = [NSFont systemFontOfSize:12.0 weight:NSFontWeightRegular];
        self.sequenceWidthField.placeholderString = @"Width";
        self.sequenceWidthField.target = self;
        self.sequenceWidthField.action = @selector(applyFreeformObjectWidth:);
        self.sequenceWidthField.enabled = NO;
        [self.sequenceWidthField.widthAnchor constraintEqualToConstant:78.0].active = YES;
        [sizeRow addArrangedSubview:self.sequenceWidthField];
        [sizeRow addArrangedSubview:[self freeformPanelLabel:@"H"
                                                                                                        size:11.0
                                                                                                    weight:NSFontWeightSemibold
                                                                                                     color:[NSColor colorWithRed:0.55 green:0.60 blue:0.68 alpha:1.0]]];
        self.sequenceHeightField = [[NSTextField alloc] initWithFrame:NSMakeRect(0.0, 0.0, 72.0, 24.0)];
        self.sequenceHeightField.translatesAutoresizingMaskIntoConstraints = NO;
        self.sequenceHeightField.font = [NSFont systemFontOfSize:12.0 weight:NSFontWeightRegular];
        self.sequenceHeightField.placeholderString = @"Height";
        self.sequenceHeightField.target = self;
        self.sequenceHeightField.action = @selector(applyFreeformObjectHeight:);
        self.sequenceHeightField.enabled = NO;
        [self.sequenceHeightField.widthAnchor constraintEqualToConstant:78.0].active = YES;
        [sizeRow addArrangedSubview:self.sequenceHeightField];
        [stack addArrangedSubview:[self freeformPanelLabel:@"Element size"
                                                                                                    size:11.0
                                                                                                weight:NSFontWeightSemibold
                                                                                                 color:[NSColor colorWithRed:0.55 green:0.60 blue:0.68 alpha:1.0]]];
        [stack addArrangedSubview:sizeRow];

        NSStackView *fillRow = [[NSStackView alloc] initWithFrame:NSZeroRect];
        fillRow.translatesAutoresizingMaskIntoConstraints = NO;
        fillRow.orientation = NSUserInterfaceLayoutOrientationHorizontal;
        fillRow.alignment = NSLayoutAttributeCenterY;
        fillRow.spacing = 10.0;
        [fillRow addArrangedSubview:[self freeformPanelLabel:@"Fill"
                                                                                                        size:11.0
                                                                                                    weight:NSFontWeightSemibold
                                                                                                     color:[NSColor colorWithRed:0.55 green:0.60 blue:0.68 alpha:1.0]]];
        self.sequenceFillColorWell = [[NSColorWell alloc] initWithFrame:NSMakeRect(0.0, 0.0, 44.0, 28.0)];
        self.sequenceFillColorWell.translatesAutoresizingMaskIntoConstraints = NO;
        self.sequenceFillColorWell.target = self;
        self.sequenceFillColorWell.action = @selector(applyFreeformFillColor:);
        self.sequenceFillColorWell.enabled = NO;
        [fillRow addArrangedSubview:self.sequenceFillColorWell];
        [stack addArrangedSubview:fillRow];

        NSStackView *strokeRow = [[NSStackView alloc] initWithFrame:NSZeroRect];
        strokeRow.translatesAutoresizingMaskIntoConstraints = NO;
        strokeRow.orientation = NSUserInterfaceLayoutOrientationHorizontal;
        strokeRow.alignment = NSLayoutAttributeCenterY;
        strokeRow.spacing = 10.0;
        [strokeRow addArrangedSubview:[self freeformPanelLabel:@"Stroke"
                                                                                                            size:11.0
                                                                                                        weight:NSFontWeightSemibold
                                                                                                         color:[NSColor colorWithRed:0.55 green:0.60 blue:0.68 alpha:1.0]]];
        self.sequenceStrokeColorWell = [[NSColorWell alloc] initWithFrame:NSMakeRect(0.0, 0.0, 44.0, 28.0)];
        self.sequenceStrokeColorWell.translatesAutoresizingMaskIntoConstraints = NO;
        self.sequenceStrokeColorWell.target = self;
        self.sequenceStrokeColorWell.action = @selector(applyFreeformStrokeColor:);
        self.sequenceStrokeColorWell.enabled = NO;
        [strokeRow addArrangedSubview:self.sequenceStrokeColorWell];
        [stack addArrangedSubview:strokeRow];

        [stack addArrangedSubview:[self freeformPanelLabel:@"Border thickness"
                                                                                                    size:11.0
                                                                                                weight:NSFontWeightSemibold
                                                                                                 color:[NSColor colorWithRed:0.55 green:0.60 blue:0.68 alpha:1.0]]];
        self.sequenceStrokeWidthSlider = [NSSlider sliderWithValue:2.0 minValue:1.0 maxValue:12.0 target:self action:@selector(applyFreeformStrokeWidth:)];
        self.sequenceStrokeWidthSlider.translatesAutoresizingMaskIntoConstraints = NO;
        self.sequenceStrokeWidthSlider.continuous = YES;
        self.sequenceStrokeWidthSlider.enabled = NO;
        [stack addArrangedSubview:self.sequenceStrokeWidthSlider];
        self.sequenceStrokeWidthValueLabel = [self freeformPanelLabel:@"2.0 pt"
                                                                                                                         size:11.0
                                                                                                                     weight:NSFontWeightRegular
                                                                                                                        color:[NSColor colorWithRed:0.79 green:0.82 blue:0.88 alpha:1.0]];
        [stack addArrangedSubview:self.sequenceStrokeWidthValueLabel];

        [stack addArrangedSubview:[self freeformSectionViewWithTitle:@"MESSAGE STYLE"
                                                                                                                     lines:@[
                                                                                                                             @"Select a sequence message to edit its label, stroke, pattern, thickness, and arrow direction.",
                                                                                                                     ]]];
        [stack addArrangedSubview:[self freeformPanelLabel:@"Message label"
                                                                                                    size:11.0
                                                                                                weight:NSFontWeightSemibold
                                                                                                 color:[NSColor colorWithRed:0.55 green:0.60 blue:0.68 alpha:1.0]]];
        self.sequenceMessageLabelField = [[NSTextField alloc] initWithFrame:NSZeroRect];
        self.sequenceMessageLabelField.translatesAutoresizingMaskIntoConstraints = NO;
        self.sequenceMessageLabelField.font = [NSFont systemFontOfSize:12.0 weight:NSFontWeightRegular];
        self.sequenceMessageLabelField.placeholderString = @"Select a message to edit its label";
        self.sequenceMessageLabelField.target = self;
        self.sequenceMessageLabelField.action = @selector(applyFreeformEdgeLabel:);
        self.sequenceMessageLabelField.enabled = NO;
        [stack addArrangedSubview:self.sequenceMessageLabelField];
        [self.sequenceMessageLabelField.widthAnchor constraintGreaterThanOrEqualToConstant:240.0].active = YES;

        NSStackView *messageColorRow = [[NSStackView alloc] initWithFrame:NSZeroRect];
        messageColorRow.translatesAutoresizingMaskIntoConstraints = NO;
        messageColorRow.orientation = NSUserInterfaceLayoutOrientationHorizontal;
        messageColorRow.alignment = NSLayoutAttributeCenterY;
        messageColorRow.spacing = 10.0;
        [messageColorRow addArrangedSubview:[self freeformPanelLabel:@"Message color"
                                                                                                                        size:11.0
                                                                                                                    weight:NSFontWeightSemibold
                                                                                                                     color:[NSColor colorWithRed:0.55 green:0.60 blue:0.68 alpha:1.0]]];
        self.sequenceMessageColorWell = [[NSColorWell alloc] initWithFrame:NSMakeRect(0.0, 0.0, 44.0, 28.0)];
        self.sequenceMessageColorWell.translatesAutoresizingMaskIntoConstraints = NO;
        self.sequenceMessageColorWell.target = self;
        self.sequenceMessageColorWell.action = @selector(applyFreeformEdgeColor:);
        self.sequenceMessageColorWell.enabled = NO;
        [messageColorRow addArrangedSubview:self.sequenceMessageColorWell];
        [stack addArrangedSubview:messageColorRow];

        [stack addArrangedSubview:[self freeformPanelLabel:@"Message thickness"
                                                                                                    size:11.0
                                                                                                weight:NSFontWeightSemibold
                                                                                                 color:[NSColor colorWithRed:0.55 green:0.60 blue:0.68 alpha:1.0]]];
        self.sequenceMessageThicknessSlider = [NSSlider sliderWithValue:2.0 minValue:1.0 maxValue:12.0 target:self action:@selector(applyFreeformEdgeThickness:)];
        self.sequenceMessageThicknessSlider.translatesAutoresizingMaskIntoConstraints = NO;
        self.sequenceMessageThicknessSlider.continuous = YES;
        self.sequenceMessageThicknessSlider.enabled = NO;
        [stack addArrangedSubview:self.sequenceMessageThicknessSlider];
        self.sequenceMessageThicknessValueLabel = [self freeformPanelLabel:@"2.0 pt"
                                                                                                                                    size:11.0
                                                                                                                                weight:NSFontWeightRegular
                                                                                                                                 color:[NSColor colorWithRed:0.79 green:0.82 blue:0.88 alpha:1.0]];
        [stack addArrangedSubview:self.sequenceMessageThicknessValueLabel];

        [stack addArrangedSubview:[self freeformPanelLabel:@"Message pattern"
                                                                                                    size:11.0
                                                                                                weight:NSFontWeightSemibold
                                                                                                 color:[NSColor colorWithRed:0.55 green:0.60 blue:0.68 alpha:1.0]]];
        self.sequenceMessagePatternPopup = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(0.0, 0.0, 220.0, 26.0) pullsDown:NO];
        self.sequenceMessagePatternPopup.translatesAutoresizingMaskIntoConstraints = NO;
        [self.sequenceMessagePatternPopup addItemsWithTitles:@[@"Solid", @"Dashed", @"Dotted", @"Thick"]];
        self.sequenceMessagePatternPopup.target = self;
        self.sequenceMessagePatternPopup.action = @selector(applyFreeformEdgePattern:);
        self.sequenceMessagePatternPopup.enabled = NO;
        [stack addArrangedSubview:self.sequenceMessagePatternPopup];

        [stack addArrangedSubview:[self freeformPanelLabel:@"Arrow direction"
                                                                                                    size:11.0
                                                                                                weight:NSFontWeightSemibold
                                                                                                 color:[NSColor colorWithRed:0.55 green:0.60 blue:0.68 alpha:1.0]]];
        self.sequenceMessageArrowPopup = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(0.0, 0.0, 220.0, 26.0) pullsDown:NO];
        self.sequenceMessageArrowPopup.translatesAutoresizingMaskIntoConstraints = NO;
        [self.sequenceMessageArrowPopup addItemsWithTitles:@[@"None", @"Forward", @"Reverse", @"Both"]];
        self.sequenceMessageArrowPopup.target = self;
        self.sequenceMessageArrowPopup.action = @selector(applyFreeformEdgeArrowMode:);
        self.sequenceMessageArrowPopup.enabled = NO;
        [stack addArrangedSubview:self.sequenceMessageArrowPopup];

        NSView *document = [[NSView alloc] initWithFrame:NSZeroRect];
        document.translatesAutoresizingMaskIntoConstraints = NO;
        [document addSubview:stack];
        [NSLayoutConstraint activateConstraints:@[
                [stack.leadingAnchor constraintEqualToAnchor:document.leadingAnchor],
                [stack.trailingAnchor constraintEqualToAnchor:document.trailingAnchor],
                [stack.topAnchor constraintEqualToAnchor:document.topAnchor],
                [stack.bottomAnchor constraintEqualToAnchor:document.bottomAnchor],
                [stack.widthAnchor constraintEqualToAnchor:document.widthAnchor],
        ]];

        NSScrollView *scrollView = [[NSScrollView alloc] initWithFrame:NSZeroRect];
        scrollView.translatesAutoresizingMaskIntoConstraints = NO;
        scrollView.hasVerticalScroller = YES;
        scrollView.hasHorizontalScroller = NO;
        scrollView.autohidesScrollers = YES;
        scrollView.borderType = NSNoBorder;
        scrollView.backgroundColor = [NSColor colorWithRed:0.10 green:0.11 blue:0.13 alpha:1.0];
        scrollView.drawsBackground = YES;
        scrollView.documentView = document;
        return scrollView;
}

- (void)syncFreeformInspectorControls {
        self.freeformSelectionLabel.stringValue = self.freeformCanvasComponent.selectionSummary ?: @"No selection";
    self.freeformCreateStatusLabel.stringValue = self.freeformCanvasComponent.insertionSummary ?: @"";
    self.freeformCancelCreateButton.enabled = self.freeformCanvasComponent.insertionModeActive;
    self.freeformCanvasBackgroundColorWell.color = self.freeformCanvasComponent.canvasBackgroundColor ?: [NSColor whiteColor];
    self.freeformCanvasBackgroundOpacitySlider.doubleValue = self.freeformCanvasComponent.canvasBackgroundOpacity;
    self.freeformCanvasBackgroundOpacityValueLabel.stringValue = [NSString stringWithFormat:@"%.0f%%", self.freeformCanvasComponent.canvasBackgroundOpacity * 100.0];
    [self syncFreeformConnectorControls];

    const BOOL hasSelection = self.freeformCanvasComponent.hasSelectedNode || self.freeformCanvasComponent.hasSelectedSubgraph;
    const BOOL hasEdgeSelection = self.freeformCanvasComponent.hasSelectedEdge;
    self.freeformNodeLabelField.enabled = hasSelection;
    self.freeformWidthField.enabled = hasSelection;
    self.freeformHeightField.enabled = hasSelection;
    self.freeformFillColorWell.enabled = hasSelection;
    self.freeformStrokeColorWell.enabled = hasSelection;
    self.freeformStrokeWidthSlider.enabled = hasSelection;
    self.freeformEdgeLabelField.enabled = hasEdgeSelection;
    self.freeformEdgeColorWell.enabled = hasEdgeSelection;
    self.freeformEdgeThicknessSlider.enabled = hasEdgeSelection;
    self.freeformEdgePatternPopup.enabled = hasEdgeSelection;
    self.freeformEdgeArrowPopup.enabled = hasEdgeSelection;

    if (!hasSelection) {
        self.freeformNodeLabelField.stringValue = @"";
        self.freeformWidthField.stringValue = @"";
        self.freeformHeightField.stringValue = @"";
        self.freeformStrokeWidthValueLabel.stringValue = @"-";
    } else {
        self.freeformNodeLabelField.stringValue = self.freeformCanvasComponent.selectedNodeLabel ?: @"";
        self.freeformWidthField.stringValue = [NSString stringWithFormat:@"%.0f", self.freeformCanvasComponent.selectedObjectWidth];
        self.freeformHeightField.stringValue = [NSString stringWithFormat:@"%.0f", self.freeformCanvasComponent.selectedObjectHeight];
        self.freeformFillColorWell.color = self.freeformCanvasComponent.selectedNodeFillColor ?: [NSColor whiteColor];
        self.freeformStrokeColorWell.color = self.freeformCanvasComponent.selectedNodeStrokeColor ?: [NSColor blackColor];
        self.freeformStrokeWidthSlider.doubleValue = self.freeformCanvasComponent.selectedNodeStrokeWidth;
        self.freeformStrokeWidthValueLabel.stringValue = [NSString stringWithFormat:@"%.1f pt", self.freeformCanvasComponent.selectedNodeStrokeWidth];
    }

    if (!hasEdgeSelection) {
        self.freeformEdgeLabelField.stringValue = @"";
        self.freeformEdgeThicknessValueLabel.stringValue = @"-";
        [self.freeformEdgePatternPopup selectItemAtIndex:0];
        [self.freeformEdgeArrowPopup selectItemAtIndex:0];
    } else {
        self.freeformEdgeLabelField.stringValue = self.freeformCanvasComponent.selectedEdgeLabel ?: @"";
        self.freeformEdgeColorWell.color = self.freeformCanvasComponent.selectedEdgeStrokeColor ?: [NSColor blackColor];
        self.freeformEdgeThicknessSlider.doubleValue = self.freeformCanvasComponent.selectedEdgeThickness;
        self.freeformEdgeThicknessValueLabel.stringValue = [NSString stringWithFormat:@"%.1f pt", self.freeformCanvasComponent.selectedEdgeThickness];
        [self.freeformEdgePatternPopup selectItemAtIndex:MAX(0, MIN(self.freeformCanvasComponent.selectedEdgeLineStyle, 3))];
        [self.freeformEdgeArrowPopup selectItemAtIndex:MAX(0, MIN(self.freeformCanvasComponent.selectedEdgeArrowMode, 3))];
    }

    self.sequenceSelectionLabel.stringValue = self.freeformCanvasComponent.selectionSummary ?: @"No selection";
    self.sequenceCanvasBackgroundColorWell.color = self.freeformCanvasComponent.canvasBackgroundColor ?: [NSColor whiteColor];
    self.sequenceCanvasBackgroundOpacitySlider.doubleValue = self.freeformCanvasComponent.canvasBackgroundOpacity;
    self.sequenceCanvasBackgroundOpacityValueLabel.stringValue = [NSString stringWithFormat:@"%.0f%%", self.freeformCanvasComponent.canvasBackgroundOpacity * 100.0];
    self.sequenceElementLabelField.enabled = hasSelection;
    self.sequenceWidthField.enabled = hasSelection;
    self.sequenceHeightField.enabled = hasSelection;
    self.sequenceFillColorWell.enabled = hasSelection;
    self.sequenceStrokeColorWell.enabled = hasSelection;
    self.sequenceStrokeWidthSlider.enabled = hasSelection;
    self.sequenceMessageLabelField.enabled = hasEdgeSelection;
    self.sequenceMessageColorWell.enabled = hasEdgeSelection;
    self.sequenceMessageThicknessSlider.enabled = hasEdgeSelection;
    self.sequenceMessagePatternPopup.enabled = hasEdgeSelection;
    self.sequenceMessageArrowPopup.enabled = hasEdgeSelection;

    if (!hasSelection) {
        self.sequenceElementLabelField.stringValue = @"";
        self.sequenceWidthField.stringValue = @"";
        self.sequenceHeightField.stringValue = @"";
        self.sequenceStrokeWidthValueLabel.stringValue = @"-";
    } else {
        self.sequenceElementLabelField.stringValue = self.freeformCanvasComponent.selectedNodeLabel ?: @"";
        self.sequenceWidthField.stringValue = [NSString stringWithFormat:@"%.0f", self.freeformCanvasComponent.selectedObjectWidth];
        self.sequenceHeightField.stringValue = [NSString stringWithFormat:@"%.0f", self.freeformCanvasComponent.selectedObjectHeight];
        self.sequenceFillColorWell.color = self.freeformCanvasComponent.selectedNodeFillColor ?: [NSColor whiteColor];
        self.sequenceStrokeColorWell.color = self.freeformCanvasComponent.selectedNodeStrokeColor ?: [NSColor blackColor];
        self.sequenceStrokeWidthSlider.doubleValue = self.freeformCanvasComponent.selectedNodeStrokeWidth;
        self.sequenceStrokeWidthValueLabel.stringValue = [NSString stringWithFormat:@"%.1f pt", self.freeformCanvasComponent.selectedNodeStrokeWidth];
    }

    if (!hasEdgeSelection) {
        self.sequenceMessageLabelField.stringValue = @"";
        self.sequenceMessageThicknessValueLabel.stringValue = @"-";
        [self.sequenceMessagePatternPopup selectItemAtIndex:0];
        [self.sequenceMessageArrowPopup selectItemAtIndex:0];
    } else {
        self.sequenceMessageLabelField.stringValue = self.freeformCanvasComponent.selectedEdgeLabel ?: @"";
        self.sequenceMessageColorWell.color = self.freeformCanvasComponent.selectedEdgeStrokeColor ?: [NSColor blackColor];
        self.sequenceMessageThicknessSlider.doubleValue = self.freeformCanvasComponent.selectedEdgeThickness;
        self.sequenceMessageThicknessValueLabel.stringValue = [NSString stringWithFormat:@"%.1f pt", self.freeformCanvasComponent.selectedEdgeThickness];
        [self.sequenceMessagePatternPopup selectItemAtIndex:MAX(0, MIN(self.freeformCanvasComponent.selectedEdgeLineStyle, 3))];
        [self.sequenceMessageArrowPopup selectItemAtIndex:MAX(0, MIN(self.freeformCanvasComponent.selectedEdgeArrowMode, 3))];
    }
}

- (BOOL)isFreeformGraphPath:(NSString *)path {
    NSString *extension = [path.pathExtension lowercaseString];
    return [extension isEqualToString:@"ffm"] || [extension isEqualToString:@"merrowgraph"];
}

- (NSString *)defaultFreeformSourcePlaceholder {
    return @"%% Freeform graph document\n%% Use Diagram > Mode > Freeform Canvas to edit this custom graph.\n";
}

- (BOOL)writeFreeformDocumentToPath:(NSString *)targetPath error:(NSError **)error {
    NSData *graphData = [self.freeformCanvasComponent serializedDocumentDataWithError:error];
    if (!graphData) {
        return NO;
    }

    NSString *source = self.editorTextView.string ?: @"";
    NSDictionary *document = @{
        @"format": @"merrow-ffm-v1",
        @"mermaidSource": source,
        @"freeformGraph": graphData,
    };

    NSData *data = [NSPropertyListSerialization dataWithPropertyList:document
                                                              format:NSPropertyListBinaryFormat_v1_0
                                                             options:0
                                                               error:error];
    if (!data) {
        return NO;
    }

    const BOOL ok = [data writeToFile:targetPath options:NSDataWritingAtomic error:error];
    if (ok) {
        self.currentDocumentIsFreeform = YES;
        self.currentSourcePath = [targetPath copy];
        [self markDocumentEdited:NO];
        self.statusLabel.stringValue = [NSString stringWithFormat:@"Saved %@", self.currentSourcePath.lastPathComponent ?: @"document"];
    }
    return ok;
}

- (BOOL)loadFreeformDocumentFromPath:(NSString *)sourcePath {
    NSError *error = nil;
    NSData *data = [NSData dataWithContentsOfFile:sourcePath options:0 error:&error];
    if (!data) {
        self.statusLabel.stringValue = [NSString stringWithFormat:@"Failed to load graph: %@", error.localizedDescription ?: @"unknown error"];
        return NO;
    }

    NSData *graphData = nil;
    NSString *source = nil;
    NSPropertyListFormat format = NSPropertyListBinaryFormat_v1_0;
    id root = [NSPropertyListSerialization propertyListWithData:data
                                                        options:NSPropertyListMutableContainersAndLeaves
                                                         format:&format
                                                          error:nil];
    if ([root isKindOfClass:[NSDictionary class]] && [[[root[@"format"] description] lowercaseString] isEqualToString:@"merrow-ffm-v1"]) {
        source = [root[@"mermaidSource"] isKindOfClass:[NSString class]] ? root[@"mermaidSource"] : @"";
        graphData = [root[@"freeformGraph"] isKindOfClass:[NSData class]] ? root[@"freeformGraph"] : nil;
        if (!graphData) {
            self.statusLabel.stringValue = @"Failed to load graph: missing freeform graph payload.";
            return NO;
        }
    } else {
        graphData = data;
        source = [self defaultFreeformSourcePlaceholder];
    }

    if (![self.freeformCanvasComponent loadSerializedDocumentData:graphData error:&error]) {
        self.statusLabel.stringValue = [NSString stringWithFormat:@"Failed to load graph: %@", error.localizedDescription ?: @"unknown error"];
        return NO;
    }

    [self applyEditorSource:source ?: [self defaultFreeformSourcePlaceholder] fromPath:sourcePath];
    self.currentDocumentIsFreeform = YES;
    self.freeformModeEnabled = YES;
    [self applyEditingModeUI];
    [self syncFreeformInspectorControls];
    self.statusLabel.stringValue = [NSString stringWithFormat:@"Loaded %@", sourcePath.lastPathComponent ?: @"graph"];
    return YES;
}

- (void)mountViewerPaneBodyView:(NSView *)bodyView {
    if (!self.viewerPaneContentHost || !bodyView) return;

    for (NSView *subview in [self.viewerPaneContentHost.subviews copy]) {
        [subview removeFromSuperview];
    }

    bodyView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.viewerPaneContentHost addSubview:bodyView];
    [NSLayoutConstraint activateConstraints:@[
        [bodyView.leadingAnchor constraintEqualToAnchor:self.viewerPaneContentHost.leadingAnchor],
        [bodyView.trailingAnchor constraintEqualToAnchor:self.viewerPaneContentHost.trailingAnchor],
        [bodyView.topAnchor constraintEqualToAnchor:self.viewerPaneContentHost.topAnchor],
        [bodyView.bottomAnchor constraintEqualToAnchor:self.viewerPaneContentHost.bottomAnchor],
    ]];
}

- (void)mountEditorPaneBodyView:(NSView *)bodyView {
    if (!self.editorPaneContentHost || !bodyView) return;

    for (NSView *subview in [self.editorPaneContentHost.subviews copy]) {
        [subview removeFromSuperview];
    }

    bodyView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.editorPaneContentHost addSubview:bodyView];
    [NSLayoutConstraint activateConstraints:@[
        [bodyView.leadingAnchor constraintEqualToAnchor:self.editorPaneContentHost.leadingAnchor],
        [bodyView.trailingAnchor constraintEqualToAnchor:self.editorPaneContentHost.trailingAnchor],
        [bodyView.topAnchor constraintEqualToAnchor:self.editorPaneContentHost.topAnchor],
        [bodyView.bottomAnchor constraintEqualToAnchor:self.editorPaneContentHost.bottomAnchor],
    ]];
}

- (void)applyEditingModeUI {
    if (self.freeformModeEnabled) {
        const BOOL isSequenceGraph = [self isSequenceFreeformGraph];
        self.viewerPaneTitleLabel.stringValue = @"Editable Canvas";
        self.viewerPaneSubtitleLabel.stringValue = isSequenceGraph ? @"Sequence-aware freeform canvas with editable participants, fragments, notes, and messages" : @"Reusable freeform object-graph component with direct selection and drag editing";
        [self mountViewerPaneBodyView:self.freeformCanvasComponent];
        self.editorPaneTitleLabel.stringValue = isSequenceGraph ? @"Sequence Properties" : @"Freeform Canvas";
        self.editorPaneSubtitleLabel.stringValue = isSequenceGraph ? @"Sequence-specific inspector and message styling workspace" : @"Tools and inspector workspace for custom object-graph editing";
        [self mountEditorPaneBodyView:[self activeFreeformInspectorScrollView]];
        self.commandField.hidden = YES;
        self.commandButton.hidden = YES;
        self.contextLabel.hidden = YES;
        self.mermaidModeMenuItem.state = NSControlStateValueOff;
        self.freeformModeMenuItem.state = NSControlStateValueOn;
        [self.window makeFirstResponder:self.freeformCanvasComponent];
    } else {
        self.viewerPaneTitleLabel.stringValue = @"Diagram View";
        self.viewerPaneSubtitleLabel.stringValue = @"Direct AppKit vector preview with pan and zoom";
        [self mountViewerPaneBodyView:self.viewerView];
        self.editorPaneTitleLabel.stringValue = @"Mermaid Source";
        self.editorPaneSubtitleLabel.stringValue = @"Editor with live highlighting and parser feedback";
        [self mountEditorPaneBodyView:self.editorScrollView];
        self.commandField.hidden = NO;
        self.commandButton.hidden = NO;
        self.contextLabel.hidden = NO;
        self.mermaidModeMenuItem.state = NSControlStateValueOn;
        self.freeformModeMenuItem.state = NSControlStateValueOff;
        [self.window makeFirstResponder:self.editorTextView];
    }
}

- (void)refreshFreeformCanvasFromEditorSource {
    NSString *source = self.editorTextView.string ?: @"";
    const char *sourceUTF8 = source.UTF8String ?: "";
    char message[256] = {0};
    const MerrowFreeformGraphSnapshot *graph = merrow_studio_build_editable_graph((const uint8_t *)sourceUTF8,
                                                                                  (uint32_t)strlen(sourceUTF8),
                                                                                  message,
                                                                                  sizeof(message));
    if (!graph) {
        [self.freeformCanvasComponent clearDocument];
        if (self.freeformModeEnabled) {
            [self applyEditingModeUI];
        }
        [self syncFreeformInspectorControls];
        self.statusLabel.stringValue = [NSString stringWithUTF8String:message[0] != 0 ? message : "Freeform canvas unavailable"]; 
        return;
    }

    [self.freeformCanvasComponent loadEditableGraph:graph];
    merrow_studio_free_editable_graph(graph);
    if (self.freeformModeEnabled) {
        [self applyEditingModeUI];
    }
    [self syncFreeformInspectorControls];
    self.statusLabel.stringValue = [NSString stringWithUTF8String:message[0] != 0 ? message : "Editable canvas ready"];
}

- (IBAction)selectEditingMode:(id)sender {
    NSString *mode = [sender representedObject];
    BOOL shouldUseFreeform = [mode isEqualToString:@"freeform"];
    if (self.freeformModeEnabled == shouldUseFreeform) {
        [self applyEditingModeUI];
        return;
    }

    self.freeformModeEnabled = shouldUseFreeform;
    [self applyEditingModeUI];
    if (self.freeformModeEnabled) {
        if (self.currentDocumentIsFreeform) {
            [self syncFreeformInspectorControls];
            self.statusLabel.stringValue = @"Freeform canvas mode enabled for current FFM document.";
        } else {
            [self refreshFreeformCanvasFromEditorSource];
        }
    } else {
        self.statusLabel.stringValue = self.currentDocumentIsFreeform ? @"Mermaid source mode enabled for current FFM document." : @"Mermaid source mode enabled.";
    }
}

- (IBAction)resetFreeformToMermaid:(id)sender {
    (void)sender;

    NSString *source = self.editorTextView.string ?: @"";
    const char *sourceUTF8 = source.UTF8String ?: "";
    char message[256] = {0};
    const MerrowFreeformGraphSnapshot *graph = merrow_studio_build_editable_graph((const uint8_t *)sourceUTF8,
                                                                                  (uint32_t)strlen(sourceUTF8),
                                                                                  message,
                                                                                  sizeof(message));
    if (!graph) {
        self.statusLabel.stringValue = [NSString stringWithUTF8String:message[0] != 0 ? message : "Unable to reset freeform canvas from Mermaid source."];
        return;
    }

    [self.freeformCanvasComponent loadEditableGraph:graph];
    merrow_studio_free_editable_graph(graph);

    if (!self.freeformModeEnabled) {
        self.freeformModeEnabled = YES;
    }

    [self applyEditingModeUI];
    [self syncFreeformInspectorControls];
    [self markDocumentEdited:YES];
    self.statusLabel.stringValue = @"Freeform canvas reset from Mermaid source.";
}

- (uint32_t)selectedFreeformShapeCode {
    NSNumber *shapeValue = [self.freeformShapePopup.selectedItem.representedObject isKindOfClass:[NSNumber class]] ? self.freeformShapePopup.selectedItem.representedObject : @1;
    return (uint32_t)shapeValue.unsignedIntValue;
}

- (IBAction)beginFreeformAddShape:(id)sender {
    (void)sender;
    [self.freeformCanvasComponent beginInsertingNodeWithShape:[self selectedFreeformShapeCode]];
    [self syncFreeformInspectorControls];
    self.statusLabel.stringValue = @"Click the canvas to place the new shape.";
    [self.window makeFirstResponder:self.freeformCanvasComponent];
}

- (IBAction)beginFreeformAddGroup:(id)sender {
    (void)sender;
    [self.freeformCanvasComponent beginInsertingSubgraph];
    [self syncFreeformInspectorControls];
    self.statusLabel.stringValue = @"Click the canvas to place the new group.";
    [self.window makeFirstResponder:self.freeformCanvasComponent];
}

- (IBAction)cancelFreeformInsertion:(id)sender {
    (void)sender;
    [self.freeformCanvasComponent cancelInsertionMode];
    [self syncFreeformInspectorControls];
    self.statusLabel.stringValue = @"Freeform insertion cancelled.";
}

- (IBAction)addFreeformConnector:(id)sender {
    (void)sender;
    NSString *sourceId = [self selectedObjectIdForPopup:self.freeformConnectorSourcePopup];
    NSString *targetId = [self selectedObjectIdForPopup:self.freeformConnectorTargetPopup];
    if (![self.freeformCanvasComponent createConnectorFromObjectId:sourceId toObjectId:targetId]) {
        self.statusLabel.stringValue = @"Choose two different shapes or groups to create a connector.";
        return;
    }
    self.statusLabel.stringValue = @"Connector added.";
}

- (IBAction)applyFreeformNodeLabel:(id)sender {
    NSTextField *field = [sender isKindOfClass:[NSTextField class]] ? (NSTextField *)sender : self.freeformNodeLabelField;
    [self.freeformCanvasComponent updateSelectedNodeLabel:field.stringValue ?: @""];
    [self markDocumentEdited:YES];
}

- (IBAction)applyFreeformCanvasBackgroundColor:(id)sender {
    NSColorWell *colorWell = [sender isKindOfClass:[NSColorWell class]] ? (NSColorWell *)sender : self.freeformCanvasBackgroundColorWell;
    [self.freeformCanvasComponent updateCanvasBackgroundColor:colorWell.color];
    [self syncFreeformInspectorControls];
    [self markDocumentEdited:YES];
}

- (IBAction)applyFreeformCanvasBackgroundOpacity:(id)sender {
    NSSlider *slider = [sender isKindOfClass:[NSSlider class]] ? (NSSlider *)sender : self.freeformCanvasBackgroundOpacitySlider;
    [self.freeformCanvasComponent updateCanvasBackgroundOpacity:slider.doubleValue];
    [self syncFreeformInspectorControls];
    [self markDocumentEdited:YES];
}

- (IBAction)applyFreeformObjectWidth:(id)sender {
    NSTextField *field = [sender isKindOfClass:[NSTextField class]] ? (NSTextField *)sender : self.freeformWidthField;
    [self.freeformCanvasComponent updateSelectedObjectWidth:MAX(1.0, field.doubleValue)];
    [self markDocumentEdited:YES];
}

- (IBAction)applyFreeformObjectHeight:(id)sender {
    NSTextField *field = [sender isKindOfClass:[NSTextField class]] ? (NSTextField *)sender : self.freeformHeightField;
    [self.freeformCanvasComponent updateSelectedObjectHeight:MAX(1.0, field.doubleValue)];
    [self markDocumentEdited:YES];
}

- (IBAction)applyFreeformFillColor:(id)sender {
    NSColorWell *colorWell = [sender isKindOfClass:[NSColorWell class]] ? (NSColorWell *)sender : self.freeformFillColorWell;
    [self.freeformCanvasComponent updateSelectedNodeFillColor:colorWell.color];
    [self markDocumentEdited:YES];
}

- (IBAction)applyFreeformStrokeColor:(id)sender {
    NSColorWell *colorWell = [sender isKindOfClass:[NSColorWell class]] ? (NSColorWell *)sender : self.freeformStrokeColorWell;
    [self.freeformCanvasComponent updateSelectedNodeStrokeColor:colorWell.color];
    [self markDocumentEdited:YES];
}

- (IBAction)applyFreeformStrokeWidth:(id)sender {
    NSSlider *slider = [sender isKindOfClass:[NSSlider class]] ? (NSSlider *)sender : self.freeformStrokeWidthSlider;
    [self.freeformCanvasComponent updateSelectedNodeStrokeWidth:slider.doubleValue];
    [self markDocumentEdited:YES];
}

- (IBAction)applyFreeformEdgeLabel:(id)sender {
    NSTextField *field = [sender isKindOfClass:[NSTextField class]] ? (NSTextField *)sender : self.freeformEdgeLabelField;
    [self.freeformCanvasComponent updateSelectedEdgeLabel:field.stringValue ?: @""];
    [self markDocumentEdited:YES];
}

- (IBAction)applyFreeformEdgeColor:(id)sender {
    NSColorWell *colorWell = [sender isKindOfClass:[NSColorWell class]] ? (NSColorWell *)sender : self.freeformEdgeColorWell;
    [self.freeformCanvasComponent updateSelectedEdgeStrokeColor:colorWell.color];
    [self markDocumentEdited:YES];
}

- (IBAction)applyFreeformEdgeThickness:(id)sender {
    NSSlider *slider = [sender isKindOfClass:[NSSlider class]] ? (NSSlider *)sender : self.freeformEdgeThicknessSlider;
    [self.freeformCanvasComponent updateSelectedEdgeThickness:slider.doubleValue];
    [self markDocumentEdited:YES];
}

- (IBAction)applyFreeformEdgePattern:(id)sender {
    NSPopUpButton *popup = [sender isKindOfClass:[NSPopUpButton class]] ? (NSPopUpButton *)sender : self.freeformEdgePatternPopup;
    [self.freeformCanvasComponent updateSelectedEdgeLineStyle:popup.indexOfSelectedItem];
    [self markDocumentEdited:YES];
}

- (IBAction)applyFreeformEdgeArrowMode:(id)sender {
    NSPopUpButton *popup = [sender isKindOfClass:[NSPopUpButton class]] ? (NSPopUpButton *)sender : self.freeformEdgeArrowPopup;
    [self.freeformCanvasComponent updateSelectedEdgeArrowMode:popup.indexOfSelectedItem];
    [self markDocumentEdited:YES];
}

- (void)freeformCanvasComponentDidChangeSelection:(MerrowFreeformCanvasComponent *)component {
    (void)component;
    [self syncFreeformInspectorControls];
}

- (void)freeformCanvasComponentDidMutateDocument:(MerrowFreeformCanvasComponent *)component {
    (void)component;
    self.freeformSelectionLabel.stringValue = self.freeformCanvasComponent.selectionSummary ?: @"No selection";
    [self syncFreeformInspectorControls];
    [self markDocumentEdited:YES];
    self.statusLabel.stringValue = @"Freeform canvas updated.";
}

- (void)applyDiagramCommandText:(NSString *)command clearCommandField:(BOOL)clearCommandField {
    NSString *trimmedCommand = [command stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (trimmedCommand.length == 0) {
        self.statusLabel.stringValue = @"Enter a diagram command first.";
        return;
    }

    const NSUInteger generation = self.editorGeneration;
    NSString *source = [self.editorTextView.string copy] ?: @"";

    dispatch_async(self.editorWorkQueue, ^{
        @autoreleasepool {
            const char *source_utf8 = source.UTF8String ?: "";
            const char *command_utf8 = trimmedCommand.UTF8String ?: "";
            const char *context_utf8 = self.currentCommandContextId.UTF8String ?: "";
            char commandMessage[256] = {0};
            char contextId[256] = {0};
            char contextDisplay[256] = {0};
            char *editedSource = merrow_studio_apply_command((const uint8_t *)source_utf8,
                                                             (uint32_t)strlen(source_utf8),
                                                             (const uint8_t *)command_utf8,
                                                             (uint32_t)strlen(command_utf8),
                                                             (const uint8_t *)context_utf8,
                                                             (uint32_t)strlen(context_utf8),
                                                             contextId,
                                                             sizeof(contextId),
                                                             contextDisplay,
                                                             sizeof(contextDisplay),
                                                             commandMessage,
                                                             sizeof(commandMessage));

            const char *messageBytes = commandMessage[0] != 0 ? commandMessage : (editedSource ? "Command applied" : "Command failed");
            NSString *message = [[NSString alloc] initWithBytes:messageBytes
                                                         length:strlen(messageBytes)
                                                       encoding:NSUTF8StringEncoding] ?: @"Command failed";
            NSString *updatedSource = nil;
            NSString *updatedContextId = nil;
            NSString *updatedContextDisplay = nil;
            if (editedSource) {
                updatedSource = [[NSString alloc] initWithBytes:editedSource
                                                         length:strlen(editedSource)
                                                       encoding:NSUTF8StringEncoding];
            }
            if (contextId[0] != 0) {
                updatedContextId = [[NSString alloc] initWithBytes:contextId
                                                            length:strlen(contextId)
                                                          encoding:NSUTF8StringEncoding] ?: @"";
            }
            if (contextDisplay[0] != 0) {
                updatedContextDisplay = [[NSString alloc] initWithBytes:contextDisplay
                                                                 length:strlen(contextDisplay)
                                                               encoding:NSUTF8StringEncoding] ?: @"";
            }
            if (editedSource) {
                merrow_studio_free_string(editedSource);
            }

            dispatch_async(dispatch_get_main_queue(), ^{
                if (generation != self.editorGeneration) {
                    self.statusLabel.stringValue = @"Command cancelled because the document changed.";
                    return;
                }

                if (updatedSource) {
                    [self replaceEditorSourceFromCommand:updatedSource status:message contextId:updatedContextId contextDisplay:updatedContextDisplay];
                    if (clearCommandField) {
                        self.commandField.stringValue = @"";
                    }
                    [self.window makeFirstResponder:self.editorTextView];
                } else {
                    self.statusLabel.stringValue = message ?: @"Command failed";
                    [self.window makeFirstResponder:clearCommandField ? self.commandField : self.editorTextView];
                }
            });
        }
    });
}

- (IBAction)runDiagramCommand:(id)sender {
    (void)sender;
    NSString *command = [self.commandField.stringValue stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    [self applyDiagramCommandText:command clearCommandField:YES];
}

- (IBAction)selectDiagramDirection:(id)sender {
    NSString *direction = [sender representedObject];
    if (direction.length == 0) {
        self.statusLabel.stringValue = @"Direction menu item is misconfigured.";
        return;
    }

    [self applyDiagramCommandText:[NSString stringWithFormat:@"direction %@", direction] clearCommandField:NO];
}

- (IBAction)shuffleDiagramLayout:(id)sender {
    (void)sender;

    const NSUInteger generation = self.editorGeneration;
    NSString *source = [self.editorTextView.string copy] ?: @"";

    dispatch_async(self.editorWorkQueue, ^{
        @autoreleasepool {
            const char *source_utf8 = source.UTF8String ?: "";
            char shuffleMessage[256] = {0};
            char *editedSource = merrow_studio_shuffle_diagram((const uint8_t *)source_utf8,
                                                               (uint32_t)strlen(source_utf8),
                                                               shuffleMessage,
                                                               sizeof(shuffleMessage));

            const char *messageBytes = shuffleMessage[0] != 0 ? shuffleMessage : (editedSource ? "Shuffle applied" : "Shuffle unavailable");
            NSString *message = [[NSString alloc] initWithBytes:messageBytes
                                                         length:strlen(messageBytes)
                                                       encoding:NSUTF8StringEncoding] ?: @"Shuffle unavailable";
            NSString *updatedSource = nil;
            if (editedSource) {
                updatedSource = [[NSString alloc] initWithBytes:editedSource
                                                         length:strlen(editedSource)
                                                       encoding:NSUTF8StringEncoding];
                merrow_studio_free_string(editedSource);
            }

            dispatch_async(dispatch_get_main_queue(), ^{
                if (generation != self.editorGeneration) {
                    self.statusLabel.stringValue = @"Shuffle cancelled because the document changed.";
                    return;
                }

                if (updatedSource) {
                    [self replaceEditorSourceFromCommand:updatedSource status:message contextId:nil contextDisplay:nil];
                    [self.window makeFirstResponder:self.editorTextView];
                } else {
                    self.statusLabel.stringValue = message;
                }
            });
        }
    });
}

- (void)processEditorChange {
    if (!self.editorTextView) return;

    const NSUInteger generation = self.editorGeneration;
    NSString *source = [self.editorTextView.string copy] ?: @"";
    NSString *fileName = self.currentSourcePath.lastPathComponent ?: @"untitled.mmd";

    dispatch_async(self.editorWorkQueue, ^{
        @autoreleasepool {
            const char *utf8 = source.UTF8String ?: "";
            char syntaxMessage[256] = {0};
            int syntaxResult = merrow_studio_check_mermaid_syntax((const uint8_t *)utf8, (uint32_t)strlen(utf8), syntaxMessage, sizeof(syntaxMessage));

            NSString *syntaxString = [NSString stringWithUTF8String:syntaxMessage[0] != 0 ? syntaxMessage : "Syntax check failed"];
            const MerrowStudioScene *scene = NULL;
            char previewPath[4096] = {0};
            char previewMessage[256] = {0};
            int previewResult = 2;

            if (syntaxResult == 0) {
                scene = merrow_studio_build_scene((const uint8_t *)utf8, (uint32_t)strlen(utf8));
                if (!scene) {
                    previewResult = merrow_studio_render_preview_png((const uint8_t *)utf8, (uint32_t)strlen(utf8), previewPath, sizeof(previewPath), previewMessage, sizeof(previewMessage));
                }
            }

            NSString *previewPathString = previewPath[0] != 0 ? [NSString stringWithUTF8String:previewPath] : nil;

            dispatch_async(dispatch_get_main_queue(), ^{
                if (generation != self.editorGeneration) {
                    if (scene) merrow_studio_free_scene(scene);
                    if (previewPathString.length > 0) {
                        [[NSFileManager defaultManager] removeItemAtPath:previewPathString error:nil];
                    }
                    return;
                }

                self.statusLabel.stringValue = [NSString stringWithFormat:@"%@ | %@", syntaxString, fileName];

                if (scene) {
                    [self.viewerRenderer replaceScene:scene];
                    [self.viewerView setNeedsDisplay:YES];
                } else if (previewResult == 0 && previewPathString.length > 0) {
                    NSImage *image = [[NSImage alloc] initWithContentsOfFile:previewPathString];
                    if (image) {
                        [self.viewerRenderer replacePreviewImage:image path:previewPathString];
                        [self.viewerView setNeedsDisplay:YES];
                    } else {
                        [[NSFileManager defaultManager] removeItemAtPath:previewPathString error:nil];
                    }
                }
            });
        }
    });
}

- (NSString *)editorDisplayName {
    return self.currentSourcePath.lastPathComponent ?: @"untitled.mmd";
}

- (NSString *)exportBaseName {
    NSString *displayName = [self editorDisplayName];
    NSString *stem = displayName.stringByDeletingPathExtension;
    return stem.length > 0 ? stem : @"diagram";
}

- (NSString *)ensurePath:(NSString *)path hasExtension:(NSString *)fileExtension {
    if (path.pathExtension.length > 0) {
        return path;
    }
    return [path stringByAppendingPathExtension:fileExtension] ?: path;
}

- (NSView *)exportAccessoryViewWithLabel:(NSString *)labelText popup:(NSPopUpButton **)outPopup options:(NSArray<NSString *> *)options {
    NSView *container = [[NSView alloc] initWithFrame:NSMakeRect(0.0, 0.0, 320.0, 32.0)];

    NSTextField *label = [NSTextField labelWithString:labelText];
    label.frame = NSMakeRect(0.0, 7.0, 80.0, 18.0);
    [container addSubview:label];

    NSPopUpButton *popup = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(92.0, 2.0, 220.0, 26.0) pullsDown:NO];
    [popup addItemsWithTitles:options];
    [popup selectItemAtIndex:0];
    [container addSubview:popup];

    if (outPopup) {
        *outPopup = popup;
    }

    return container;
}

- (void)runExportForFormat:(uint32_t)format
           defaultExtension:(NSString *)fileExtension
                 panelTitle:(NSString *)panelTitle
                optionLabel:(NSString *)optionLabel
               optionTitles:(NSArray<NSString *> *)optionTitles
               rasterScales:(NSArray<NSNumber *> *)rasterScales
               layoutScales:(NSArray<NSNumber *> *)layoutScales {
    NSSavePanel *panel = [NSSavePanel savePanel];
    panel.title = panelTitle;
    panel.canCreateDirectories = YES;
    MerrowSetAllowedFileTypes(panel, @[ fileExtension ]);
    panel.nameFieldStringValue = [NSString stringWithFormat:@"%@.%@", [self exportBaseName], fileExtension];

    NSString *directory = self.currentSourcePath.stringByDeletingLastPathComponent;
    if (directory.length > 0) {
        panel.directoryURL = [NSURL fileURLWithPath:directory];
    }

    NSPopUpButton *popup = nil;
    panel.accessoryView = [self exportAccessoryViewWithLabel:optionLabel popup:&popup options:optionTitles];

    [panel beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse response) {
        if (response != NSModalResponseOK || panel.URL.path.length == 0) {
            return;
        }

        NSInteger selectedIndex = popup.indexOfSelectedItem;
        if (selectedIndex < 0 || selectedIndex >= (NSInteger)MIN(rasterScales.count, layoutScales.count)) {
            selectedIndex = 0;
        }

        NSString *exportPath = [self ensurePath:panel.URL.path hasExtension:fileExtension];
        const double rasterScale = rasterScales[(NSUInteger)selectedIndex].doubleValue;
        const double layoutScale = layoutScales[(NSUInteger)selectedIndex].doubleValue;
        if (self.currentDocumentIsFreeform || self.freeformModeEnabled) {
            NSError *error = nil;
            BOOL ok = NO;
            if (format == 0) {
                ok = [self.freeformCanvasComponent writePNGExportToPath:exportPath scale:rasterScale error:&error];
            } else {
                ok = [self.freeformCanvasComponent writeSVGExportToPath:exportPath scale:layoutScale error:&error];
            }
            if (ok) {
                NSString *kind = format == 0 ? @"Freeform PNG exported" : @"Freeform SVG exported";
                self.statusLabel.stringValue = [NSString stringWithFormat:@"%@: %@", kind, exportPath.lastPathComponent ?: exportPath];
            } else {
                self.statusLabel.stringValue = [NSString stringWithFormat:@"Export failed: %@", error.localizedDescription ?: @"unknown error"];
            }
        } else {
            NSString *source = self.editorTextView.string ?: @"";
            const char *utf8 = source.UTF8String ?: "";
            char exportMessage[256] = {0};
            const int exportResult = merrow_studio_export_diagram((const uint8_t *)utf8,
                                                                  (uint32_t)strlen(utf8),
                                                                  exportPath.UTF8String,
                                                                  format,
                                                                  rasterScale,
                                                                  layoutScale,
                                                                  exportMessage,
                                                                  sizeof(exportMessage));

            NSString *message = [NSString stringWithUTF8String:exportMessage[0] != 0 ? exportMessage : "Export finished"];
            if (exportResult == 0) {
                self.statusLabel.stringValue = [NSString stringWithFormat:@"%@: %@", message, exportPath.lastPathComponent ?: exportPath];
            } else {
                self.statusLabel.stringValue = [NSString stringWithFormat:@"Export failed: %@", message];
            }
        }
    }];
}

- (void)updateWindowTitle {
    if (!self.window) return;

    NSString *displayName = [self editorDisplayName];
    self.window.title = [NSString stringWithFormat:@"%@ - Merrow Studio", displayName];
    self.window.representedURL = self.currentSourcePath != nil ? [NSURL fileURLWithPath:self.currentSourcePath] : nil;
}

- (void)markDocumentEdited:(BOOL)edited {
    [self.window setDocumentEdited:edited];
    [self updateWindowTitle];
}

- (void)applyEditorSource:(NSString *)source fromPath:(NSString *)sourcePath {
    self.isSynchronizingEditor = YES;
    self.currentSourcePath = [sourcePath copy];
    self.currentDocumentIsFreeform = sourcePath.length > 0 && [self isFreeformGraphPath:sourcePath];
    [self.editorTextView setString:source ?: @""];
    [self applySyntaxHighlighting];
    self.editorGeneration += 1;
    [self requestEditorAnalysis];
    [self.editorTextView setSelectedRange:NSMakeRange(0, 0)];
    [self.editorTextView scrollRangeToVisible:NSMakeRange(0, 0)];
    self.isSynchronizingEditor = NO;
    [self clearCommandContext];
    [self markDocumentEdited:NO];
}

- (BOOL)writeEditorSourceToPath:(NSString *)targetPath error:(NSError **)error {
    if (targetPath.length == 0) {
        if (error) {
            *error = [NSError errorWithDomain:NSCocoaErrorDomain code:NSFileNoSuchFileError userInfo:@{ NSLocalizedDescriptionKey: @"No target file path was provided." }];
        }
        return NO;
    }

    NSString *source = self.editorTextView.string ?: @"";
    BOOL ok = [source writeToFile:targetPath atomically:YES encoding:NSUTF8StringEncoding error:error];
    if (ok) {
        self.currentSourcePath = [targetPath copy];
        [self markDocumentEdited:NO];
        self.statusLabel.stringValue = [NSString stringWithFormat:@"Saved %@", self.currentSourcePath.lastPathComponent ?: @"document"];
    }
    return ok;
}

- (BOOL)writeCurrentDocumentToPath:(NSString *)targetPath error:(NSError **)error {
    if (self.freeformModeEnabled || [self isFreeformGraphPath:targetPath] || self.currentDocumentIsFreeform) {
        return [self writeFreeformDocumentToPath:targetPath error:error];
    }
    return [self writeEditorSourceToPath:targetPath error:error];
}

- (void)runSavePanelForPath:(NSString *)suggestedPath completion:(void (^)(BOOL saved))completion {
    NSSavePanel *panel = [NSSavePanel savePanel];
    panel.canCreateDirectories = YES;
    const BOOL savingFreeformDocument = self.freeformModeEnabled || self.currentDocumentIsFreeform;
    MerrowSetAllowedFileTypes(panel, savingFreeformDocument ? @[ @"ffm" ] : @[ @"mmd", @"mermaid", @"txt" ]);
    panel.nameFieldStringValue = suggestedPath.lastPathComponent ?: [self editorDisplayName];
    if (suggestedPath.stringByDeletingLastPathComponent.length > 0) {
        panel.directoryURL = [NSURL fileURLWithPath:suggestedPath.stringByDeletingLastPathComponent];
    }

    [panel beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse response) {
        if (response != NSModalResponseOK || panel.URL.path.length == 0) {
            if (completion) completion(NO);
            return;
        }

        NSError *error = nil;
        BOOL saved = [self writeCurrentDocumentToPath:panel.URL.path error:&error];
        if (!saved) {
            self.statusLabel.stringValue = [NSString stringWithFormat:@"Save failed: %@", error.localizedDescription ?: @"unknown error"];
        }
        if (completion) completion(saved);
    }];
}

- (void)performSaveWithSaveAs:(BOOL)saveAs completion:(void (^)(BOOL saved))completion {
    if (!saveAs && self.currentSourcePath.length > 0) {
        NSError *error = nil;
        BOOL saved = [self writeCurrentDocumentToPath:self.currentSourcePath error:&error];
        if (!saved) {
            self.statusLabel.stringValue = [NSString stringWithFormat:@"Save failed: %@", error.localizedDescription ?: @"unknown error"];
        }
        if (completion) completion(saved);
        return;
    }

    NSString *suggestedPath = self.currentSourcePath;
    if (suggestedPath.length == 0) {
        const BOOL savingFreeformDocument = self.freeformModeEnabled || self.currentDocumentIsFreeform;
        suggestedPath = [NSTemporaryDirectory() stringByAppendingPathComponent:(savingFreeformDocument ? @"untitled.ffm" : [self editorDisplayName])];
    }
    [self runSavePanelForPath:suggestedPath completion:completion];
}

- (void)promptToSaveIfNeededThen:(void (^)(BOOL shouldContinue))completion {
    if (!self.window.documentEdited) {
        if (completion) completion(YES);
        return;
    }

    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = [NSString stringWithFormat:@"Save changes to %@?", [self editorDisplayName]];
    alert.informativeText = @"Your Mermaid source has unsaved changes.";
    [alert addButtonWithTitle:@"Save"];
    [alert addButtonWithTitle:@"Don't Save"];
    [alert addButtonWithTitle:@"Cancel"];

    [alert beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse response) {
        if (response == NSAlertFirstButtonReturn) {
            [self performSaveWithSaveAs:NO completion:^(BOOL saved) {
                if (completion) completion(saved);
            }];
            return;
        }

        if (response == NSAlertSecondButtonReturn) {
            if (completion) completion(YES);
            return;
        }

        if (completion) completion(NO);
    }];
}

- (void)loadEditorSourceFromPath:(NSString *)sourcePath {
    if ([self isFreeformGraphPath:sourcePath]) {
        [self loadFreeformDocumentFromPath:sourcePath];
        return;
    }

    NSError *error = nil;
    NSString *source = [NSString stringWithContentsOfFile:sourcePath encoding:NSUTF8StringEncoding error:&error];
    if (!source) {
        self.statusLabel.stringValue = [NSString stringWithFormat:@"Failed to load source: %@", error.localizedDescription ?: @"unknown error"];
        return;
    }

    self.currentDocumentIsFreeform = NO;
    [self applyEditorSource:source fromPath:sourcePath];
}

- (void)textDidChange:(NSNotification *)notification {
    if (notification.object != self.editorTextView || self.isApplyingHighlighting || self.isSynchronizingEditor) return;
    self.editorGeneration += 1;
    [self clearCommandContext];
    [self markDocumentEdited:YES];
    [self debounceSyntaxHighlighting];
    [self requestEditorAnalysis];
}

- (IBAction)newDocument:(id)sender {
    (void)sender;
    [self promptToSaveIfNeededThen:^(BOOL shouldContinue) {
        if (!shouldContinue) return;
        [self applyEditorSource:MerrowStudioUntitledSource() fromPath:nil];
        self.statusLabel.stringValue = @"New Mermaid document.";
    }];
}

- (IBAction)openDocument:(id)sender {
    (void)sender;
    [self promptToSaveIfNeededThen:^(BOOL shouldContinue) {
        if (!shouldContinue) return;

        NSOpenPanel *panel = [NSOpenPanel openPanel];
        panel.canChooseFiles = YES;
        panel.canChooseDirectories = NO;
        panel.allowsMultipleSelection = NO;
        MerrowSetAllowedFileTypes(panel, @[ @"mmd", @"mermaid", @"txt", @"md", @"ffm", @"merrowgraph" ]);

        [panel beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse response) {
            if (response != NSModalResponseOK || panel.URL.path.length == 0) return;
            [self loadEditorSourceFromPath:panel.URL.path];
        }];
    }];
}

- (IBAction)saveDocument:(id)sender {
    (void)sender;
    [self performSaveWithSaveAs:NO completion:nil];
}

- (IBAction)saveDocumentAs:(id)sender {
    (void)sender;
    [self performSaveWithSaveAs:YES completion:nil];
}

- (IBAction)exportFreeformDocument:(id)sender {
    (void)sender;
    if (!self.freeformModeEnabled && !self.currentDocumentIsFreeform) {
        self.statusLabel.stringValue = @"Switch to Freeform Canvas mode before exporting an FFM document.";
        return;
    }
    [self performSaveWithSaveAs:YES completion:nil];
}

- (IBAction)importFreeformDocument:(id)sender {
    (void)sender;
    [self promptToSaveIfNeededThen:^(BOOL shouldContinue) {
        if (!shouldContinue) return;

        NSOpenPanel *panel = [NSOpenPanel openPanel];
        panel.canChooseFiles = YES;
        panel.canChooseDirectories = NO;
        panel.allowsMultipleSelection = NO;
        MerrowSetAllowedFileTypes(panel, @[ @"ffm", @"merrowgraph" ]);

        [panel beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse response) {
            if (response != NSModalResponseOK || panel.URL.path.length == 0) return;
            [self loadFreeformDocumentFromPath:panel.URL.path];
        }];
    }];
}

- (IBAction)exportDocumentAsPNG:(id)sender {
    (void)sender;
    [self runExportForFormat:0
            defaultExtension:@"png"
                  panelTitle:@"Export Diagram as PNG"
                 optionLabel:@"Quality:"
                optionTitles:@[
                    @"Standard (2x)",
                    @"High (3x)",
                    @"Print (4x)",
                ]
                rasterScales:@[
                    @2.0,
                    @3.0,
                    @4.0,
                ]
                layoutScales:@[
                    @1.0,
                    @1.0,
                    @1.0,
                ]];
}

- (IBAction)exportDocumentAsSVG:(id)sender {
    (void)sender;
    [self runExportForFormat:1
            defaultExtension:@"svg"
                  panelTitle:@"Export Diagram as SVG"
                 optionLabel:@"Scale:"
                optionTitles:@[
                    @"Standard (1x)",
                    @"Large (1.25x)",
                    @"Presentation (1.5x)",
                ]
                rasterScales:@[
                    @1.0,
                    @1.0,
                    @1.0,
                ]
                layoutScales:@[
                    @1.0,
                    @1.25,
                    @1.5,
                ]];
}

- (void)installMenuBar {
    NSMenu *menuBar = [[NSMenu alloc] initWithTitle:@""];

    NSMenuItem *appMenuItem = [[NSMenuItem alloc] initWithTitle:@"Merrow Studio" action:nil keyEquivalent:@""];
    [menuBar addItem:appMenuItem];

    NSMenuItem *editMenuItem = [[NSMenuItem alloc] initWithTitle:@"Edit" action:nil keyEquivalent:@""];
    [menuBar addItem:editMenuItem];

    NSMenuItem *fileMenuItem = [[NSMenuItem alloc] initWithTitle:@"File" action:nil keyEquivalent:@""];
    [menuBar addItem:fileMenuItem];

    NSMenuItem *diagramMenuItem = [[NSMenuItem alloc] initWithTitle:@"Diagram" action:nil keyEquivalent:@""];
    [menuBar addItem:diagramMenuItem];

    NSMenuItem *freeformMenuItem = [[NSMenuItem alloc] initWithTitle:@"Freeform" action:nil keyEquivalent:@""];
    [menuBar addItem:freeformMenuItem];

    NSMenu *appMenu = [[NSMenu alloc] initWithTitle:@"Merrow Studio"];
    NSString *quitTitle = @"Quit Merrow Studio";
    NSMenuItem *quitItem = [[NSMenuItem alloc] initWithTitle:quitTitle
                                                      action:@selector(terminate:)
                                               keyEquivalent:@"q"];
    [appMenu addItem:quitItem];
    [appMenuItem setSubmenu:appMenu];

    NSMenu *editMenu = [[NSMenu alloc] initWithTitle:@"Edit"];

    NSMenuItem *undoItem = [[NSMenuItem alloc] initWithTitle:@"Undo" action:@selector(undo:) keyEquivalent:@"z"];
    [editMenu addItem:undoItem];

    NSMenuItem *redoItem = [[NSMenuItem alloc] initWithTitle:@"Redo" action:@selector(redo:) keyEquivalent:@"Z"];
    [editMenu addItem:redoItem];

    [editMenuItem setSubmenu:editMenu];

    NSMenu *fileMenu = [[NSMenu alloc] initWithTitle:@"File"];

    NSMenuItem *newItem = [[NSMenuItem alloc] initWithTitle:@"New" action:@selector(newDocument:) keyEquivalent:@"n"];
    newItem.target = self;
    [fileMenu addItem:newItem];

    NSMenuItem *openItem = [[NSMenuItem alloc] initWithTitle:@"Open..." action:@selector(openDocument:) keyEquivalent:@"o"];
    openItem.target = self;
    [fileMenu addItem:openItem];

    [fileMenu addItem:[NSMenuItem separatorItem]];

    NSMenuItem *saveItem = [[NSMenuItem alloc] initWithTitle:@"Save" action:@selector(saveDocument:) keyEquivalent:@"s"];
    saveItem.target = self;
    [fileMenu addItem:saveItem];

    NSMenuItem *saveAsItem = [[NSMenuItem alloc] initWithTitle:@"Save As..." action:@selector(saveDocumentAs:) keyEquivalent:@"S"];
    saveAsItem.target = self;
    [fileMenu addItem:saveAsItem];

    [fileMenu addItem:[NSMenuItem separatorItem]];

    NSMenuItem *importFFMItem = [[NSMenuItem alloc] initWithTitle:@"Import Freeform..." action:@selector(importFreeformDocument:) keyEquivalent:@""];
    importFFMItem.target = self;
    [fileMenu addItem:importFFMItem];

    NSMenuItem *exportFFMItem = [[NSMenuItem alloc] initWithTitle:@"Export Freeform..." action:@selector(exportFreeformDocument:) keyEquivalent:@""];
    exportFFMItem.target = self;
    [fileMenu addItem:exportFFMItem];

    [fileMenu addItem:[NSMenuItem separatorItem]];

    NSMenuItem *exportPNGItem = [[NSMenuItem alloc] initWithTitle:@"Export as PNG..." action:@selector(exportDocumentAsPNG:) keyEquivalent:@""];
    exportPNGItem.target = self;
    [fileMenu addItem:exportPNGItem];

    NSMenuItem *exportSVGItem = [[NSMenuItem alloc] initWithTitle:@"Export as SVG..." action:@selector(exportDocumentAsSVG:) keyEquivalent:@""];
    exportSVGItem.target = self;
    [fileMenu addItem:exportSVGItem];

    [fileMenuItem setSubmenu:fileMenu];

    NSMenu *diagramMenu = [[NSMenu alloc] initWithTitle:@"Diagram"];
    NSMenuItem *modeMenuItem = [[NSMenuItem alloc] initWithTitle:@"Mode" action:nil keyEquivalent:@""];
    NSMenu *modeMenu = [[NSMenu alloc] initWithTitle:@"Mode"];

    self.mermaidModeMenuItem = [[NSMenuItem alloc] initWithTitle:@"Mermaid Source" action:@selector(selectEditingMode:) keyEquivalent:@""];
    self.mermaidModeMenuItem.target = self;
    self.mermaidModeMenuItem.representedObject = @"mermaid";
    [modeMenu addItem:self.mermaidModeMenuItem];

    self.freeformModeMenuItem = [[NSMenuItem alloc] initWithTitle:@"Freeform Canvas" action:@selector(selectEditingMode:) keyEquivalent:@""];
    self.freeformModeMenuItem.target = self;
    self.freeformModeMenuItem.representedObject = @"freeform";
    [modeMenu addItem:self.freeformModeMenuItem];

    [modeMenuItem setSubmenu:modeMenu];
    [diagramMenu addItem:modeMenuItem];

    [diagramMenu addItem:[NSMenuItem separatorItem]];

    NSMenuItem *shuffleItem = [[NSMenuItem alloc] initWithTitle:@"Shuffle Layout" action:@selector(shuffleDiagramLayout:) keyEquivalent:@""];
    shuffleItem.target = self;
    [diagramMenu addItem:shuffleItem];

    [diagramMenu addItem:[NSMenuItem separatorItem]];

    NSMenuItem *directionMenuItem = [[NSMenuItem alloc] initWithTitle:@"Direction" action:nil keyEquivalent:@""];
    NSMenu *directionMenu = [[NSMenu alloc] initWithTitle:@"Direction"];

    NSMenuItem *topBottomItem = [[NSMenuItem alloc] initWithTitle:@"Top to Bottom" action:@selector(selectDiagramDirection:) keyEquivalent:@""];
    topBottomItem.target = self;
    topBottomItem.representedObject = @"TB";
    [directionMenu addItem:topBottomItem];

    NSMenuItem *leftRightItem = [[NSMenuItem alloc] initWithTitle:@"Left to Right" action:@selector(selectDiagramDirection:) keyEquivalent:@""];
    leftRightItem.target = self;
    leftRightItem.representedObject = @"LR";
    [directionMenu addItem:leftRightItem];

    NSMenuItem *rightLeftItem = [[NSMenuItem alloc] initWithTitle:@"Right to Left" action:@selector(selectDiagramDirection:) keyEquivalent:@""];
    rightLeftItem.target = self;
    rightLeftItem.representedObject = @"RL";
    [directionMenu addItem:rightLeftItem];

    NSMenuItem *bottomTopItem = [[NSMenuItem alloc] initWithTitle:@"Bottom to Top" action:@selector(selectDiagramDirection:) keyEquivalent:@""];
    bottomTopItem.target = self;
    bottomTopItem.representedObject = @"BT";
    [directionMenu addItem:bottomTopItem];

    [directionMenuItem setSubmenu:directionMenu];
    [diagramMenu addItem:directionMenuItem];

    [diagramMenuItem setSubmenu:diagramMenu];

    NSMenu *freeformMenu = [[NSMenu alloc] initWithTitle:@"Freeform"];

    NSMenuItem *resetToMermaidItem = [[NSMenuItem alloc] initWithTitle:@"Reset to Mermaid" action:@selector(resetFreeformToMermaid:) keyEquivalent:@""];
    resetToMermaidItem.target = self;
    [freeformMenu addItem:resetToMermaidItem];

    [freeformMenuItem setSubmenu:freeformMenu];

    [NSApp setMainMenu:menuBar];
}

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    (void)notification;

    [self installMenuBar];

    NSRect frame = NSMakeRect(0, 0, 1500, 920);
    self.window = [[NSWindow alloc] initWithContentRect:frame
                                              styleMask:NSWindowStyleMaskTitled |
                                                        NSWindowStyleMaskClosable |
                                                        NSWindowStyleMaskResizable |
                                                        NSWindowStyleMaskMiniaturizable
                                                backing:NSBackingStoreBuffered
                                                  defer:NO];
        self.window.delegate = self;
    [self.window center];
    [self.window setTitle:@"Merrow Studio"];
    [self.window makeKeyAndOrderFront:nil];

    if (@available(macOS 11.0, *)) {
        [self.window setToolbarStyle:NSWindowToolbarStyleUnified];
    }

    NSView *contentView = self.window.contentView;
    contentView.wantsLayer = YES;
    contentView.layer.backgroundColor = NSColor.windowBackgroundColor.CGColor;

    NSView *statusBar = [[NSView alloc] initWithFrame:NSZeroRect];
    statusBar.translatesAutoresizingMaskIntoConstraints = NO;
    statusBar.wantsLayer = YES;
    statusBar.layer.backgroundColor = [NSColor colorWithRed:0.93 green:0.94 blue:0.95 alpha:1.0].CGColor;

    self.statusLabel = [NSTextField labelWithString:@"Studio ready."];
    self.statusLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.statusLabel.textColor = [NSColor colorWithRed:0.22 green:0.24 blue:0.28 alpha:1.0];
    self.statusLabel.font = [NSFont systemFontOfSize:12.0 weight:NSFontWeightMedium];
    [statusBar addSubview:self.statusLabel];

    self.contextLabel = [NSTextField labelWithString:@"it=-"];
    self.contextLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.contextLabel.textColor = [NSColor colorWithRed:0.31 green:0.33 blue:0.38 alpha:1.0];
    self.contextLabel.font = [NSFont monospacedSystemFontOfSize:11.0 weight:NSFontWeightRegular];
    self.contextLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    [statusBar addSubview:self.contextLabel];

    self.commandButton = [NSButton buttonWithTitle:@"Apply" target:self action:@selector(runDiagramCommand:)];
    self.commandButton.translatesAutoresizingMaskIntoConstraints = NO;
    self.commandButton.bezelStyle = NSBezelStyleRounded;
    [statusBar addSubview:self.commandButton];

    self.commandField = [[NSTextField alloc] initWithFrame:NSZeroRect];
    self.commandField.translatesAutoresizingMaskIntoConstraints = NO;
    self.commandField.placeholderString = @"Command: connect alpha to beta, delete box alpha, direction LR";
    self.commandField.font = [NSFont systemFontOfSize:12.0 weight:NSFontWeightRegular];
    self.commandField.target = self;
    self.commandField.action = @selector(runDiagramCommand:);
    [statusBar addSubview:self.commandField];

    self.splitView = [[NSSplitView alloc] initWithFrame:NSZeroRect];
    self.splitView.translatesAutoresizingMaskIntoConstraints = NO;
    self.splitView.dividerStyle = NSSplitViewDividerStyleThin;
    self.splitView.vertical = YES;
    self.splitView.wantsLayer = YES;
    self.splitView.delegate = self;
    self.splitView.autosaveName = @"MerrowStudioMainSplit";

    self.editorWorkQueue = dispatch_queue_create("com.merrow.studio.editor-work", DISPATCH_QUEUE_SERIAL);

    MerrowViewportView *viewer = [[MerrowViewportView alloc] initWithFrame:NSZeroRect];
    viewer.translatesAutoresizingMaskIntoConstraints = NO;

    self.viewerRenderer = [[MerrowSceneRenderer alloc] init];
    self.viewerView = viewer;
    viewer.viewportRenderer = self.viewerRenderer;

    NSTextStorage *textStorage = [[NSTextStorage alloc] init];
    NSLayoutManager *layoutManager = [[NSLayoutManager alloc] init];
    layoutManager.allowsNonContiguousLayout = YES;
    [textStorage addLayoutManager:layoutManager];

    NSTextContainer *textContainer = [[NSTextContainer alloc] initWithContainerSize:NSMakeSize(CGFLOAT_MAX, CGFLOAT_MAX)];
    textContainer.widthTracksTextView = YES;
    [layoutManager addTextContainer:textContainer];

    textContainer.heightTracksTextView = NO;

    self.editorTextView = [[MerrowEditorTextView alloc] initWithFrame:NSMakeRect(0.0, 0.0, 640.0, 900.0) textContainer:textContainer];
    self.editorTextView.translatesAutoresizingMaskIntoConstraints = YES;
    self.editorTextView.delegate = self;
    self.editorTextView.editable = YES;
    self.editorTextView.selectable = YES;
    self.editorTextView.richText = NO;
    self.editorTextView.usesFontPanel = NO;
    self.editorTextView.drawsBackground = YES;
    self.editorTextView.automaticQuoteSubstitutionEnabled = NO;
    self.editorTextView.automaticDashSubstitutionEnabled = NO;
    self.editorTextView.automaticTextReplacementEnabled = NO;
    self.editorTextView.automaticSpellingCorrectionEnabled = NO;
    self.editorTextView.automaticDataDetectionEnabled = NO;
    self.editorTextView.allowsUndo = YES;
    self.editorTextView.horizontallyResizable = NO;
    self.editorTextView.verticallyResizable = YES;
    self.editorTextView.minSize = NSMakeSize(0.0, 0.0);
    self.editorTextView.maxSize = NSMakeSize(CGFLOAT_MAX, CGFLOAT_MAX);
    self.editorTextView.autoresizingMask = NSViewWidthSizable;
    self.editorTextView.textContainerInset = NSMakeSize(14.0, 16.0);
    self.editorTextView.backgroundColor = [NSColor colorWithRed:0.10 green:0.11 blue:0.13 alpha:1.0];
    self.editorTextView.insertionPointColor = [NSColor colorWithRed:0.95 green:0.96 blue:0.98 alpha:1.0];
    self.editorTextView.textColor = [NSColor colorWithRed:0.86 green:0.88 blue:0.91 alpha:1.0];
    self.editorTextView.font = [NSFont fontWithName:@"Menlo-Regular" size:14.0] ?: [NSFont monospacedSystemFontOfSize:14.0 weight:NSFontWeightRegular];
    self.editorTextView.typingAttributes = [self baseEditorAttributes];
    self.editorTextView.usesFindBar = YES;
    self.editorTextView.postsFrameChangedNotifications = YES;

    self.editorScrollView = [[NSScrollView alloc] initWithFrame:NSZeroRect];
    self.editorScrollView.translatesAutoresizingMaskIntoConstraints = NO;
    self.editorScrollView.hasVerticalScroller = YES;
    self.editorScrollView.hasHorizontalScroller = NO;
    self.editorScrollView.autohidesScrollers = YES;
    self.editorScrollView.borderType = NSNoBorder;
    self.editorScrollView.backgroundColor = self.editorTextView.backgroundColor;
    self.editorScrollView.documentView = self.editorTextView;
    [self.editorTextView setMinSize:NSMakeSize(0.0, 900.0)];
    [textContainer setContainerSize:NSMakeSize(640.0, CGFLOAT_MAX)];

    char sourcePath[4096] = {0};
    const MerrowStudioScene *defaultScene = merrow_studio_create_default_scene(sourcePath, sizeof(sourcePath));
    if (defaultScene) {
        NSString *sourcePathString = [NSString stringWithUTF8String:sourcePath];
        [self.viewerRenderer replaceScene:defaultScene];
        [self loadEditorSourceFromPath:sourcePathString];
    } else {
        self.statusLabel.stringValue = @"Preview scene creation failed.";
    }
    [viewer setNeedsDisplay:YES];

    self.viewerPaneContentHost = [[NSView alloc] initWithFrame:NSZeroRect];
    self.viewerPaneContentHost.translatesAutoresizingMaskIntoConstraints = NO;
    self.freeformCanvasComponent = [[MerrowFreeformCanvasComponent alloc] initWithFrame:NSZeroRect];
    self.freeformCanvasComponent.translatesAutoresizingMaskIntoConstraints = NO;
    self.freeformCanvasComponent.delegate = self;
    self.viewerPane = [self wrappedPaneWithTitle:@"Diagram View" subtitle:@"Direct AppKit vector preview with pan and zoom" bodyView:self.viewerPaneContentHost dark:NO titleLabel:&_viewerPaneTitleLabel subtitleLabel:&_viewerPaneSubtitleLabel];
    [self mountViewerPaneBodyView:viewer];

    self.editorPaneContentHost = [[NSView alloc] initWithFrame:NSZeroRect];
    self.editorPaneContentHost.translatesAutoresizingMaskIntoConstraints = NO;
    self.freeformToolsScrollView = [self createFreeformToolsScrollView];
    self.sequenceToolsScrollView = [self createSequenceToolsScrollView];
    self.editorPane = [self wrappedPaneWithTitle:@"Mermaid Source" subtitle:@"Editor with live highlighting and parser feedback" bodyView:self.editorPaneContentHost dark:YES titleLabel:&_editorPaneTitleLabel subtitleLabel:&_editorPaneSubtitleLabel];
    [self mountEditorPaneBodyView:self.editorScrollView];

    [self.splitView addArrangedSubview:self.viewerPane];
    [self.splitView addArrangedSubview:self.editorPane];
    [self.splitView setHoldingPriority:NSLayoutPriorityDefaultLow forSubviewAtIndex:0];
    [self.splitView setHoldingPriority:NSLayoutPriorityDefaultLow forSubviewAtIndex:1];

    [contentView addSubview:self.splitView];
    [contentView addSubview:statusBar];

    [NSLayoutConstraint activateConstraints:@[
        [self.splitView.leadingAnchor constraintEqualToAnchor:contentView.leadingAnchor],
        [self.splitView.trailingAnchor constraintEqualToAnchor:contentView.trailingAnchor],
        [self.splitView.topAnchor constraintEqualToAnchor:contentView.topAnchor],
        [self.splitView.bottomAnchor constraintEqualToAnchor:statusBar.topAnchor],

        [statusBar.leadingAnchor constraintEqualToAnchor:contentView.leadingAnchor],
        [statusBar.trailingAnchor constraintEqualToAnchor:contentView.trailingAnchor],
        [statusBar.bottomAnchor constraintEqualToAnchor:contentView.bottomAnchor],
        [statusBar.heightAnchor constraintEqualToConstant:34.0],

        [self.statusLabel.leadingAnchor constraintEqualToAnchor:statusBar.leadingAnchor constant:12.0],
        [self.statusLabel.centerYAnchor constraintEqualToAnchor:statusBar.centerYAnchor],

        [self.contextLabel.leadingAnchor constraintEqualToAnchor:self.statusLabel.trailingAnchor constant:12.0],
        [self.contextLabel.centerYAnchor constraintEqualToAnchor:statusBar.centerYAnchor],
        [self.contextLabel.widthAnchor constraintLessThanOrEqualToConstant:220.0],

        [self.commandButton.trailingAnchor constraintEqualToAnchor:statusBar.trailingAnchor constant:-12.0],
        [self.commandButton.centerYAnchor constraintEqualToAnchor:statusBar.centerYAnchor],

        [self.commandField.trailingAnchor constraintEqualToAnchor:self.commandButton.leadingAnchor constant:-8.0],
        [self.commandField.centerYAnchor constraintEqualToAnchor:statusBar.centerYAnchor],
        [self.commandField.widthAnchor constraintGreaterThanOrEqualToConstant:320.0],
        [self.commandField.leadingAnchor constraintGreaterThanOrEqualToAnchor:self.contextLabel.trailingAnchor constant:16.0],
    ]];

    [contentView layoutSubtreeIfNeeded];
    [self positionDividerForCurrentWindowWidth];
    [self applyEditingModeUI];

    [NSApp activateIgnoringOtherApps:YES];
    [self.editorTextView setSelectedRange:NSMakeRange(0, 0)];
    [self.editorTextView scrollRangeToVisible:NSMakeRange(0, 0)];
    [self updateWindowTitle];
}

- (CGFloat)splitView:(NSSplitView *)splitView constrainMinCoordinate:(CGFloat)proposedMinimumPosition ofSubviewAt:(NSInteger)dividerIndex {
    (void)splitView;
    (void)dividerIndex;
    return 320.0;
}

- (CGFloat)splitView:(NSSplitView *)splitView constrainMaxCoordinate:(CGFloat)proposedMaximumPosition ofSubviewAt:(NSInteger)dividerIndex {
    (void)dividerIndex;
    return splitView.bounds.size.width - 320.0;
}

- (BOOL)splitView:(NSSplitView *)splitView canCollapseSubview:(NSView *)subview {
    (void)splitView;
    (void)subview;
    return NO;
}

- (void)windowDidResize:(NSNotification *)notification {
    (void)notification;
    [self positionDividerForCurrentWindowWidth];
}

- (void)windowDidBecomeKey:(NSNotification *)notification {
    if (notification.object != self.window) return;
    if (self.freeformModeEnabled) {
        if (self.window.firstResponder != self.freeformCanvasComponent) {
            [self.window makeFirstResponder:self.freeformCanvasComponent];
        }
        return;
    }
    if (self.window.firstResponder != self.editorTextView) {
        [self.window makeFirstResponder:self.editorTextView];
    }
}

- (void)positionDividerForCurrentWindowWidth {
    if (!self.splitView || self.splitView.subviews.count < 2) return;

    const CGFloat totalWidth = self.splitView.bounds.size.width;
    if (totalWidth <= 0.0) return;

    const CGFloat desiredLeftWidth = floor(totalWidth * 0.64);
    const CGFloat clampedLeftWidth = fmax(320.0, fmin(desiredLeftWidth, totalWidth - 320.0));
    [self.splitView setPosition:clampedLeftWidth ofDividerAtIndex:0];
}

- (NSView *)wrappedPaneWithTitle:(NSString *)title subtitle:(NSString *)subtitle bodyView:(NSView *)bodyView dark:(BOOL)dark titleLabel:(NSTextField * __strong *)outTitleLabel subtitleLabel:(NSTextField * __strong *)outSubtitleLabel {
    NSView *container = [[NSView alloc] initWithFrame:NSZeroRect];
    container.translatesAutoresizingMaskIntoConstraints = YES;
    container.wantsLayer = YES;
    container.layer.backgroundColor = (dark ? [NSColor colorWithRed:0.10 green:0.11 blue:0.13 alpha:1.0] : [NSColor colorWithRed:0.96 green:0.97 blue:0.98 alpha:1.0]).CGColor;

    NSTextField *titleLabel = [NSTextField labelWithString:title];
    titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    titleLabel.font = [NSFont systemFontOfSize:13.0 weight:NSFontWeightSemibold];
    titleLabel.textColor = dark ? [NSColor colorWithRed:0.95 green:0.96 blue:0.98 alpha:1.0] : [NSColor colorWithRed:0.18 green:0.20 blue:0.24 alpha:1.0];

    NSTextField *subtitleLabel = [NSTextField labelWithString:subtitle];
    subtitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    subtitleLabel.font = [NSFont systemFontOfSize:11.0 weight:NSFontWeightRegular];
    subtitleLabel.textColor = dark ? [NSColor colorWithRed:0.62 green:0.65 blue:0.70 alpha:1.0] : [NSColor colorWithRed:0.42 green:0.45 blue:0.50 alpha:1.0];

    if (outTitleLabel) *outTitleLabel = titleLabel;
    if (outSubtitleLabel) *outSubtitleLabel = subtitleLabel;

    NSBox *separator = [[NSBox alloc] initWithFrame:NSZeroRect];
    separator.translatesAutoresizingMaskIntoConstraints = NO;
    separator.boxType = NSBoxSeparator;

    [container addSubview:titleLabel];
    [container addSubview:subtitleLabel];
    [container addSubview:separator];
    [container addSubview:bodyView];

    [NSLayoutConstraint activateConstraints:@[
        [titleLabel.leadingAnchor constraintEqualToAnchor:container.leadingAnchor constant:14.0],
        [titleLabel.topAnchor constraintEqualToAnchor:container.topAnchor constant:12.0],

        [subtitleLabel.leadingAnchor constraintEqualToAnchor:titleLabel.leadingAnchor],
        [subtitleLabel.topAnchor constraintEqualToAnchor:titleLabel.bottomAnchor constant:2.0],

        [separator.leadingAnchor constraintEqualToAnchor:container.leadingAnchor],
        [separator.trailingAnchor constraintEqualToAnchor:container.trailingAnchor],
        [separator.topAnchor constraintEqualToAnchor:subtitleLabel.bottomAnchor constant:10.0],

        [bodyView.leadingAnchor constraintEqualToAnchor:container.leadingAnchor],
        [bodyView.trailingAnchor constraintEqualToAnchor:container.trailingAnchor],
        [bodyView.topAnchor constraintEqualToAnchor:separator.bottomAnchor],
        [bodyView.bottomAnchor constraintEqualToAnchor:container.bottomAnchor],
    ]];

    return container;
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender {
    (void)sender;
    return YES;
}

- (NSApplicationTerminateReply)applicationShouldTerminate:(NSApplication *)sender {
    (void)sender;
    if (!self.window.documentEdited) {
        return NSTerminateNow;
    }

    [self promptToSaveIfNeededThen:^(BOOL shouldContinue) {
        [NSApp replyToApplicationShouldTerminate:shouldContinue];
    }];
    return NSTerminateLater;
}

- (BOOL)windowShouldClose:(id)sender {
    if (sender != self.window || !self.window.documentEdited) {
        return YES;
    }

    [self promptToSaveIfNeededThen:^(BOOL shouldContinue) {
        if (shouldContinue) {
            [self.window setDocumentEdited:NO];
            [self.window close];
        }
    }];
    return NO;
}

@end

int merrow_studio_main(int argc, const char *argv[]) {
    (void)argc;
    (void)argv;

    @autoreleasepool {
        NSApplication *app = [NSApplication sharedApplication];
        MerrowStudioAppDelegate *delegate = [[MerrowStudioAppDelegate alloc] init];
        [app setActivationPolicy:NSApplicationActivationPolicyRegular];
        [app setDelegate:delegate];
        [app run];
    }

    return 0;
}